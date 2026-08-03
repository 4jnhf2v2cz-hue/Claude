export interface Topic {
  slug: string;
  title: string;
  /** Public-domain lyrics, when this is a classic rhyme. Never invented by the LLM. */
  lyrics?: string[];
  /** For original concept videos (colors, numbers, shapes...) instead of a classic rhyme. */
  concept?: string;
  ageRange: "0-3";
  tags: string[];
}

export interface Scene {
  sceneNumber: number;
  captionText: string;
  visualPrompt: string;
  durationSeconds: number;
}

export interface Script {
  topicSlug: string;
  videoTitle: string;
  videoDescription: string;
  tags: string[];
  scenes: Scene[];
}

export interface PipelinePaths {
  root: string;
  scriptFile: string;
  audioDir: string;
  scenesDir: string;
  finalVideo: string;
  thumbnail: string;
}
