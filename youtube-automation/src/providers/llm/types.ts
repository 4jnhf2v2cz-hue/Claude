import { Script, Topic } from "../../types.js";

export interface ScriptWriter {
  writeScript(topic: Topic): Promise<Script>;
}
