import { describe, expect, test } from "bun:test";
import { parseMirrorResponse } from "../server";

describe("parseMirrorResponse", () => {
  test("accepts a markdown file and derives the title from the H1", () => {
    expect(
      parseMirrorResponse("# small truth\n\nhey, thanks for being who you are. my thoughts:\n\nbody"),
    ).toEqual({
      title: "small truth",
      reflection: "# small truth\n\nhey, thanks for being who you are. my thoughts:\n\nbody",
    });
  });

  test("accepts fenced markdown but stores only the markdown document", () => {
    expect(parseMirrorResponse("```markdown\n# quiet thread\n\nbody\n```")).toEqual({
      title: "quiet thread",
      reflection: "# quiet thread\n\nbody",
    });
  });

  test("falls back to the first line when no heading exists", () => {
    expect(parseMirrorResponse("quiet thread\n\nbody")).toEqual({
      title: "quiet thread",
      reflection: "quiet thread\n\nbody",
    });
  });

  test("rejects an empty response", () => {
    expect(() => parseMirrorResponse("   ")).toThrow("INVALID_MIRROR_RESPONSE");
  });
});
