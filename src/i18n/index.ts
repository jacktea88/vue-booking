import { createI18n } from 'vue-i18n'
import en from './en'
import fr from './fr'
import ar from './ar'

export const SUPPORTED_LOCALES = ['ar', 'fr', 'en'] as const
export type AppLocale = (typeof SUPPORTED_LOCALES)[number]
export const RTL_LOCALES: AppLocale[] = ['ar']
export const LOCALE_STORAGE_KEY = 'wassalni.locale'
export const LOCALE_LABELS: Record<AppLocale, string> = { ar: 'العربية', fr: 'Français', en: 'English' }

function initialLocale(): AppLocale {
  const stored = typeof localStorage !== 'undefined' ? localStorage.getItem(LOCALE_STORAGE_KEY) : null
  if (stored && (SUPPORTED_LOCALES as readonly string[]).includes(stored)) return stored as AppLocale
  const env = (import.meta.env?.VITE_DEFAULT_LOCALE as AppLocale) || 'fr'
  return (SUPPORTED_LOCALES as readonly string[]).includes(env) ? env : 'fr'
}

export const i18n = createI18n({
  legacy: false,
  locale: initialLocale(),
  fallbackLocale: 'fr',
  messages: { en, fr, ar },
})

export function isRtl(locale: string): boolean { return RTL_LOCALES.includes(locale as AppLocale) }

/** Applies locale to vue-i18n, <html lang/dir> and persistent storage. */
export function applyLocale(locale: AppLocale): void {
  ;(i18n.global.locale as unknown as { value: string }).value = locale
  if (typeof document !== 'undefined') {
    document.documentElement.lang = locale
    document.documentElement.dir = isRtl(locale) ? 'rtl' : 'ltr'
  }
  if (typeof localStorage !== 'undefined') localStorage.setItem(LOCALE_STORAGE_KEY, locale)
}
