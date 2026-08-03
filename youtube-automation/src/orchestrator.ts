#!/usr/bin/env node
import "dotenv/config";
import { Command } from "commander";
import { findTopic, listTopics, markProduced, nextTopic } from "./pipeline/topicQueue.js";
import { runScriptStep, loadScript } from "./pipeline/script.js";
import { runVoiceStep } from "./pipeline/voice.js";
import { runVideoStep } from "./pipeline/video.js";
import { runAssembleStep } from "./pipeline/assemble.js";
import { runThumbnailStep } from "./pipeline/thumbnail.js";
import { runUploadStep } from "./pipeline/upload.js";
import { pathsFor } from "./pipeline/paths.js";
import { Topic } from "./types.js";

const program = new Command();
program
  .name("ytauto")
  .description("Nursery-rhyme/toddler-cartoon channel automation pipeline")
  .option("--dry-run", "force mock providers even if API keys are set", false);

async function resolveTopic(topicOpt?: string): Promise<Topic> {
  return topicOpt ? findTopic(topicOpt) : nextTopic();
}

program
  .command("topics")
  .description("List every topic in the catalog and whether it's been produced")
  .action(() => {
    for (const t of listTopics()) {
      console.log(`${t.slug}\t${t.title}`);
    }
  });

program
  .command("script")
  .description("Generate the script (title/description/tags/scene prompts) for a topic")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .action(async (opts, cmd) => {
    const forceMock = cmd.optsWithGlobals().dryRun;
    const topic = await resolveTopic(opts.topic);
    await runScriptStep(topic, forceMock);
  });

program
  .command("voice")
  .description("Synthesize narration audio for each scene")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .action(async (opts, cmd) => {
    const forceMock = cmd.optsWithGlobals().dryRun;
    const topic = await resolveTopic(opts.topic);
    const script = await loadScript(topic.slug);
    await runVoiceStep(script, forceMock);
  });

program
  .command("video")
  .description("Generate video clips for each scene")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .option("--scene <n>", "generate just this one scene number (spend credit incrementally)")
  .action(async (opts, cmd) => {
    const forceMock = cmd.optsWithGlobals().dryRun;
    const topic = await resolveTopic(opts.topic);
    const script = await loadScript(topic.slug);
    const sceneNumber = opts.scene ? parseInt(opts.scene, 10) : undefined;
    await runVideoStep(script, forceMock, sceneNumber);
  });

program
  .command("assemble")
  .description("Combine scene clips + narration into the final video")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .action(async (opts) => {
    const topic = await resolveTopic(opts.topic);
    const script = await loadScript(topic.slug);
    const paths = await pathsFor(topic.slug);
    const { readdir } = await import("node:fs/promises");
    const path = await import("node:path");

    const sceneFiles = (await readdir(paths.scenesDir))
      .filter((f) => f.endsWith(".mp4"))
      .sort((a, b) => sceneNumber(a) - sceneNumber(b))
      .map((f) => path.join(paths.scenesDir, f));

    const audioFiles = (await readdir(paths.audioDir))
      .sort((a, b) => sceneNumber(a) - sceneNumber(b))
      .map((f) => path.join(paths.audioDir, f));

    await runAssembleStep(script, sceneFiles, audioFiles);
  });

program
  .command("thumbnail")
  .description("Generate a thumbnail (local only, no API key needed)")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .action(async (opts) => {
    const topic = await resolveTopic(opts.topic);
    const script = await loadScript(topic.slug);
    await runThumbnailStep(script);
  });

program
  .command("upload")
  .description("Upload the final video to YouTube (always private/unlisted by default — see README)")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .option("--confirm", "required flag to actually call the YouTube API", false)
  .action(async (opts) => {
    if (!opts.confirm) {
      console.error(
        "Refusing to upload without --confirm. This is the one step that touches your " +
          "real YouTube channel — re-run with --confirm once you've reviewed the local " +
          "output/<topic>/final.mp4 and thumbnail.jpg."
      );
      process.exitCode = 1;
      return;
    }
    const topic = await resolveTopic(opts.topic);
    const script = await loadScript(topic.slug);
    await runUploadStep(script);
  });

program
  .command("run")
  .description("Run the full pipeline (script -> voice -> video -> assemble -> thumbnail) for one topic. Upload is separate and requires its own --confirm.")
  .option("--topic <slug>", "topic slug (defaults to the next un-produced one)")
  .action(async (opts, cmd) => {
    const forceMock = cmd.optsWithGlobals().dryRun;
    const topic = await resolveTopic(opts.topic);
    console.log(`\n=== ${topic.title} (${topic.slug}) ===\n`);

    const script = await runScriptStep(topic, forceMock);
    const audioFiles = await runVoiceStep(script, forceMock);
    const videoFiles = await runVideoStep(script, forceMock);
    await runAssembleStep(script, videoFiles, audioFiles);
    await runThumbnailStep(script);
    await markProduced(topic.slug);

    console.log(
      `\nDone. Review output/${topic.slug}/final.mp4 and thumbnail.jpg, then run:\n` +
        `  npm run cli -- upload --topic ${topic.slug} --confirm\n` +
        "when you're ready to send it to YouTube (uploads private by default)."
    );
  });

function sceneNumber(filename: string): number {
  const match = filename.match(/scene-(\d+)/);
  return match ? parseInt(match[1], 10) : 0;
}

program.parseAsync(process.argv);
