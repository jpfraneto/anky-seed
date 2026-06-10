import protocolMarkdown from '../legal/protocol.md?raw'
import privacyMarkdown from '../legal/privacy.md?raw'
import termsMarkdown from '../legal/terms.md?raw'
import PageShell from './PageShell'

export type LegalRoute = 'protocol' | 'privacy' | 'terms'

const documents: Record<LegalRoute, { label: string; markdown: string }> = {
  protocol: { label: 'Protocol', markdown: protocolMarkdown },
  privacy: { label: 'Privacy', markdown: privacyMarkdown },
  terms: { label: 'Terms', markdown: termsMarkdown },
}

type LegalPageProps = {
  currentPath: string
  route: LegalRoute
  onNavigate: (href: string) => void
}

type Block =
  | { type: 'code'; content: string }
  | { type: 'heading'; level: number; content: string }
  | { type: 'hr' }
  | { type: 'quote'; content: string }
  | { type: 'list'; items: string[] }
  | { type: 'paragraph'; content: string }

function parseMarkdown(markdown: string) {
  const lines = markdown.split('\n')
  const blocks: Block[] = []
  let paragraph: string[] = []
  let list: string[] = []
  let code: string[] | null = null

  function flushParagraph() {
    if (paragraph.length > 0) {
      blocks.push({ type: 'paragraph', content: paragraph.join(' ') })
      paragraph = []
    }
  }

  function flushList() {
    if (list.length > 0) {
      blocks.push({ type: 'list', items: list })
      list = []
    }
  }

  for (const line of lines) {
    if (line.startsWith('```')) {
      if (code) {
        blocks.push({ type: 'code', content: code.join('\n') })
        code = null
      } else {
        flushParagraph()
        flushList()
        code = []
      }
      continue
    }

    if (code) {
      code.push(line)
      continue
    }

    const trimmed = line.trim()
    if (!trimmed) {
      flushParagraph()
      flushList()
      continue
    }

    if (trimmed === '---') {
      flushParagraph()
      flushList()
      blocks.push({ type: 'hr' })
      continue
    }

    if (trimmed.startsWith('#')) {
      flushParagraph()
      flushList()
      const match = trimmed.match(/^(#{1,4})\s+(.*)$/)
      if (match) {
        blocks.push({ type: 'heading', level: match[1].length, content: match[2] })
        continue
      }
    }

    if (trimmed.startsWith('>')) {
      flushParagraph()
      flushList()
      blocks.push({ type: 'quote', content: trimmed.replace(/^>\s?/, '') })
      continue
    }

    if (trimmed.startsWith('- ')) {
      flushParagraph()
      list.push(trimmed.slice(2))
      continue
    }

    paragraph.push(trimmed)
  }

  flushParagraph()
  flushList()
  return blocks
}

function inlineText(text: string) {
  const normalized = text
    .replace(/\*\*(.*?)\*\*/g, '$1')
    .replace(/\*(.*?)\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')

  const linkMatch = normalized.match(/^\[([^\]]+)\]\(([^)]+)\)$/)
  if (linkMatch) {
    return (
      <a className="text-gold-200 underline decoration-gold-200/40 underline-offset-4" href={linkMatch[2]}>
        {linkMatch[1]}
      </a>
    )
  }

  return normalized
}

function LegalPage({ currentPath, route, onNavigate }: LegalPageProps) {
  const document = documents[route]
  const blocks = parseMarkdown(document.markdown)

  return (
    <PageShell currentPath={currentPath} onNavigate={onNavigate}>
      <p className="text-xs uppercase text-gold-200/70">{document.label}</p>
      <div className="mt-8 space-y-5">
        {blocks.map((block, index) => {
          if (block.type === 'heading') {
            const className =
              block.level === 1
                ? 'font-serif text-5xl leading-tight text-cream'
                : block.level === 2
                  ? 'pt-8 font-serif text-3xl text-cream'
                  : 'pt-5 text-xl font-semibold text-gold-100'
            const Heading = `h${Math.min(block.level, 3)}` as 'h1' | 'h2' | 'h3'
            return (
              <Heading className={className} key={index}>
                {inlineText(block.content)}
              </Heading>
            )
          }

          if (block.type === 'hr') {
            return <hr className="border-gold-200/12" key={index} />
          }

          if (block.type === 'quote') {
            return (
              <blockquote className="rounded-lg border border-gold-200/14 bg-gold-200/7 p-5 leading-7 text-gold-100/82" key={index}>
                {inlineText(block.content)}
              </blockquote>
            )
          }

          if (block.type === 'list') {
            return (
              <ul className="list-disc space-y-2 pl-6 leading-7 text-cream/74" key={index}>
                {block.items.map((item) => (
                  <li key={item}>{inlineText(item)}</li>
                ))}
              </ul>
            )
          }

          if (block.type === 'code') {
            return (
              <pre className="overflow-x-auto rounded-lg border border-gold-200/10 bg-black/55 p-4 text-sm leading-6 text-cream/78" key={index}>
                <code>{block.content}</code>
              </pre>
            )
          }

          return (
            <p className="leading-8 text-cream/74" key={index}>
              {inlineText(block.content)}
            </p>
          )
        })}
      </div>
    </PageShell>
  )
}

export default LegalPage
