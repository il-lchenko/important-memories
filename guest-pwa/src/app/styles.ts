import type { CSSProperties } from 'react'

export type QrPreset = 'classic' | 'dark' | 'warm' | 'mono'
export const QR_PRESETS: Record<QrPreset, { label: string; canvas: string; modules: string; glow: string; dark: boolean }> = {
  classic: { label: 'Классика', canvas: '#F6F2E8', modules: '#1A1714', glow: 'rgba(255,179,71,.25)', dark: false },
  dark: { label: 'Тёмная', canvas: '#1F1812', modules: '#FFB347', glow: 'rgba(255,179,71,.2)', dark: true },
  warm: { label: 'Тёплая', canvas: '#F3E3C8', modules: '#1A1714', glow: 'rgba(201,136,30,.33)', dark: false },
  mono: { label: 'Моно', canvas: '#FFFFFF', modules: '#000000', glow: 'rgba(0,0,0,.1)', dark: false },
}
export function parseQrPreset(v?: string | null): QrPreset {
  return v && v in QR_PRESETS ? (v as QrPreset) : 'classic'
}

export type TitleFont = 'playfair' | 'fraunces' | 'caveat' | 'manrope'
export const TITLE_FONTS: Record<TitleFont, { label: string; style: CSSProperties }> = {
  playfair: { label: 'Playfair', style: { fontFamily: "'Playfair Display', serif", fontWeight: 700, letterSpacing: '-0.5px', lineHeight: 1.1 } },
  fraunces: { label: 'Fraunces', style: { fontFamily: "'Fraunces', serif", fontWeight: 600, letterSpacing: '-0.6px', lineHeight: 1.05 } },
  caveat: { label: 'Caveat', style: { fontFamily: "'Caveat', cursive", fontWeight: 600, lineHeight: 1 } },
  manrope: { label: 'Manrope', style: { fontFamily: "'Manrope', sans-serif", fontWeight: 800, letterSpacing: '-1px', lineHeight: 1.1 } },
}
export function parseTitleFont(v?: string | null): TitleFont {
  return v && v in TITLE_FONTS ? (v as TitleFont) : 'playfair'
}
