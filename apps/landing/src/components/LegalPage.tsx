import { useEffect } from 'react'
import protocolMarkdown from '../legal/protocol.md?raw'
import privacyDE from '../../../ios/Anky/de.lproj/PrivacyPolicy.md?raw'
import termsDE from '../../../ios/Anky/de.lproj/TermsAndConditions.md?raw'
import privacyEN from '../../../ios/Anky/en.lproj/PrivacyPolicy.md?raw'
import termsEN from '../../../ios/Anky/en.lproj/TermsAndConditions.md?raw'
import privacyES from '../../../ios/Anky/es.lproj/PrivacyPolicy.md?raw'
import termsES from '../../../ios/Anky/es.lproj/TermsAndConditions.md?raw'
import privacyFR from '../../../ios/Anky/fr.lproj/PrivacyPolicy.md?raw'
import termsFR from '../../../ios/Anky/fr.lproj/TermsAndConditions.md?raw'
import privacyHI from '../../../ios/Anky/hi.lproj/PrivacyPolicy.md?raw'
import termsHI from '../../../ios/Anky/hi.lproj/TermsAndConditions.md?raw'
import privacyZH from '../../../ios/Anky/zh-Hans.lproj/PrivacyPolicy.md?raw'
import termsZH from '../../../ios/Anky/zh-Hans.lproj/TermsAndConditions.md?raw'
import type { LegalDocumentKind, LegalLocale, LegalRoute } from '../legalRoutes'
import PageShell from './PageShell'

const localizedDocuments: Record<LegalLocale, Partial<Record<LegalDocumentKind, string>>> = {
  en: { privacy: privacyEN, protocol: protocolMarkdown, terms: termsEN },
  es: { privacy: privacyES, terms: termsES },
  fr: { privacy: privacyFR, terms: termsFR },
  de: { privacy: privacyDE, terms: termsDE },
  'zh-Hans': { privacy: privacyZH, terms: termsZH },
  hi: { privacy: privacyHI, terms: termsHI },
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

  const linkPattern = /\[([^\]]+)\]\(([^)]+)\)/g
  const pieces: Array<string | React.ReactElement> = []
  let cursor = 0
  for (const match of normalized.matchAll(linkPattern)) {
    const index = match.index ?? 0
    if (index > cursor) pieces.push(normalized.slice(cursor, index))
    pieces.push(
      <a
        className="text-gold-200 underline decoration-gold-200/40 underline-offset-4"
        href={match[2]}
        key={`${index}-${match[2]}`}
      >
        {match[1]}
      </a>,
    )
    cursor = index + match[0].length
  }
  if (cursor < normalized.length) pieces.push(normalized.slice(cursor))
  return pieces.length > 0 ? pieces : normalized
}

function LegalPage({ currentPath, route, onNavigate }: LegalPageProps) {
  const markdown = localizedDocuments[route.locale][route.kind]
  if (!markdown) {
    throw new Error(`Missing ${route.locale} ${route.kind} legal document`)
  }
  const blocks = parseMarkdown(markdown)

  useEffect(() => {
    document.title = route.pageTitle
    document.documentElement.lang = route.locale
  }, [route.locale, route.pageTitle])

  return (
    <PageShell currentPath={currentPath} onNavigate={onNavigate}>
      <p className="text-xs uppercase text-gold-200/70">{route.label}</p>
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
