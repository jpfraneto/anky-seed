import { describe, expect, test } from "bun:test";
import { parseMirrorResponse } from "../src";

describe("parseMirrorResponse", () => {
  test("accepts strict JSON", () => {
    expect(parseMirrorResponse('{"title":"small truth","reflection":"body"}')).toEqual({
      title: "small truth",
      reflection: "body",
    });
  });

  test("accepts fenced JSON", () => {
    expect(parseMirrorResponse('```json\n{"title":"small truth","reflection":"body"}\n```')).toEqual({
      title: "small truth",
      reflection: "body",
    });
  });

  test("extracts the first balanced object from wrapper text", () => {
    const raw = 'Here is the JSON:\n{"title":"small truth","reflection":"body with {braces}"}\nDone.';

    expect(parseMirrorResponse(raw)).toEqual({
      title: "small truth",
      reflection: "body with {braces}",
    });
  });

  test("accepts JSON followed by trailing prose", () => {
    const raw = '{"title":"small truth","reflection":"body"}\n\nHope this helps.';

    expect(parseMirrorResponse(raw)).toEqual({
      title: "small truth",
      reflection: "body",
    });
  });

  test("still rejects objects without the expected shape", () => {
    expect(() => parseMirrorResponse('{"title":"small truth"}')).toThrow("INVALID_MIRROR_RESPONSE");
  });
});
