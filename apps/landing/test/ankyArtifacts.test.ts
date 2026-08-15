import { describe, expect, test } from "bun:test";
import { getAnkyArtifact, youForgotMe } from "../src/content/ankyArtifacts";

describe("Anky artifacts", () => {
  test("keeps the writing as the root and the mirror as a thread", () => {
    expect(getAnkyArtifact("you-forgot-me")).toBe(youForgotMe);
    expect(getAnkyArtifact("missing")).toBeUndefined();
    expect("reflection" in youForgotMe).toBe(false);
    expect(youForgotMe.writing.durationSeconds).toBe(480);
    expect(youForgotMe.thread.messages).toHaveLength(7);
    expect(youForgotMe.thread.messages[0]?.author).toBe("ANKY");
    expect(youForgotMe.thread.messages[0]?.body).toStartWith(
      "# The Door You Built",
    );
    expect(youForgotMe.thread.messages.at(-1)?.body).toStartWith(
      "# The Artifact Is the Thread",
    );
  });
});
