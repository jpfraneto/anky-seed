import type { ReactNode } from "react";

type EditorialMarkdownProps = {
  markdown: string;
};

type MarkdownBlock =
  | { type: "code"; body: string }
  | { type: "heading"; level: number; body: string }
  | { type: "list"; ordered: boolean; items: string[] }
  | { type: "paragraph"; body: string }
  | { type: "quote"; body: string };

function parseBlocks(markdown: string) {
  const lines = markdown.split("\n");
  const blocks: MarkdownBlock[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();

    if (!trimmed) {
      index += 1;
      continue;
    }

    if (trimmed.startsWith("```")) {
      const code: string[] = [];
      index += 1;
      while (index < lines.length && !lines[index].trim().startsWith("```")) {
        code.push(lines[index]);
        index += 1;
      }
      blocks.push({ type: "code", body: code.join("\n") });
      index += 1;
      continue;
    }

    const heading = trimmed.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      blocks.push({
        type: "heading",
        level: heading[1].length,
        body: heading[2],
      });
      index += 1;
      continue;
    }

    if (trimmed.startsWith(">")) {
      const quote: string[] = [];
      while (index < lines.length && lines[index].trim().startsWith(">")) {
        quote.push(lines[index].trim().replace(/^>\s?/, ""));
        index += 1;
      }
      blocks.push({ type: "quote", body: quote.join("\n") });
      continue;
    }

    const listItem = trimmed.match(/^([-*]|\d+\.)\s+(.+)$/);
    if (listItem) {
      const ordered = /\d+\./.test(listItem[1]);
      const items: string[] = [];
      while (index < lines.length) {
        const item = lines[index].trim().match(/^([-*]|\d+\.)\s+(.+)$/);
        if (!item || /\d+\./.test(item[1]) !== ordered) {
          break;
        }
        items.push(item[2]);
        index += 1;
      }
      blocks.push({ type: "list", ordered, items });
      continue;
    }

    const paragraph: string[] = [];
    while (index < lines.length && lines[index].trim()) {
      const candidate = lines[index].trim();
      if (
        candidate.startsWith("```") ||
        /^(#{1,6})\s+/.test(candidate) ||
        candidate.startsWith(">") ||
        /^([-*]|\d+\.)\s+/.test(candidate)
      ) {
        break;
      }
      paragraph.push(lines[index]);
      index += 1;
    }
    blocks.push({ type: "paragraph", body: paragraph.join("\n") });
  }

  return blocks;
}

function inlineMarkdown(text: string): ReactNode[] {
  const tokenPattern = /(\[[^\]]+\]\([^)]+\)|\*\*[\s\S]+?\*\*|\*[^*\n]+\*|`[^`\n]+`| {2}\n|\n)/g;
  const output: ReactNode[] = [];
  let cursor = 0;
  let match: RegExpExecArray | null;

  while ((match = tokenPattern.exec(text)) !== null) {
    if (match.index > cursor) {
      output.push(text.slice(cursor, match.index));
    }

    const token = match[0];
    const link = token.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (link) {
      output.push(
        <a
          className="text-gold-100 underline decoration-gold-300/45 underline-offset-4 transition hover:text-white"
          href={link[2]}
          key={`${match.index}-${link[2]}`}
        >
          {link[1]}
        </a>,
      );
    } else if (token.startsWith("**")) {
      output.push(
        <strong className="font-semibold text-cream" key={match.index}>
          {inlineMarkdown(token.slice(2, -2))}
        </strong>,
      );
    } else if (token.startsWith("*")) {
      output.push(
        <em className="text-cream/90" key={match.index}>
          {token.slice(1, -1)}
        </em>,
      );
    } else if (token.startsWith("`")) {
      output.push(
        <code
          className="rounded bg-black/35 px-1.5 py-0.5 font-mono text-[0.88em] text-gold-100"
          key={match.index}
        >
          {token.slice(1, -1)}
        </code>,
      );
    } else if (token.includes("\n")) {
      output.push(<br key={match.index} />);
    }

    cursor = match.index + token.length;
  }

  if (cursor < text.length) {
    output.push(text.slice(cursor));
  }

  return output;
}

function EditorialMarkdown({ markdown }: EditorialMarkdownProps) {
  const blocks = parseBlocks(markdown);

  return (
    <div className="space-y-6 font-serif text-[1.12rem] leading-[1.82] text-cream/82 sm:text-[1.22rem]">
      {blocks.map((block, index) => {
        const key = `${block.type}-${index}`;

        if (block.type === "heading") {
          if (block.level === 1) {
            return (
              <h3
                className="pt-5 font-serif text-3xl leading-tight text-cream sm:text-4xl"
                key={key}
              >
                {inlineMarkdown(block.body)}
              </h3>
            );
          }

          return (
            <h4
              className="pt-6 font-sans text-sm font-semibold uppercase tracking-[0.18em] text-gold-200/88 sm:text-base"
              key={key}
            >
              {inlineMarkdown(block.body)}
            </h4>
          );
        }

        if (block.type === "quote") {
          return (
            <blockquote
              className="border-l border-gold-300/55 py-1 pl-5 text-cream/68 italic sm:pl-7"
              key={key}
            >
              {inlineMarkdown(block.body)}
            </blockquote>
          );
        }

        if (block.type === "list") {
          const List = block.ordered ? "ol" : "ul";
          return (
            <List
              className={`${block.ordered ? "list-decimal" : "list-disc"} space-y-2 pl-6 marker:text-gold-300/70`}
              key={key}
            >
              {block.items.map((item, itemIndex) => (
                <li key={`${itemIndex}-${item}`}>{inlineMarkdown(item)}</li>
              ))}
            </List>
          );
        }

        if (block.type === "code") {
          return (
            <pre
              className="max-w-full overflow-x-auto border-y border-gold-200/12 bg-black/25 px-4 py-5 font-mono text-sm leading-6 text-cream/68 sm:px-6"
              key={key}
            >
              <code>{block.body}</code>
            </pre>
          );
        }

        return (
          <p key={key}>{inlineMarkdown(block.body)}</p>
        );
      })}
    </div>
  );
}

export default EditorialMarkdown;
