/** Formatting helpers — no business rule lives here. */
export function formatDzd(amount: number, locale = 'fr'): string {
  const n = new Intl.NumberFormat(locale === 'ar' ? 'ar-DZ' : locale === 'en' ? 'en-DZ' : 'fr-DZ', {
    maximumFractionDigits: 0,
  }).format(Math.round(amount))
  return locale === 'ar' ? `${n} دج` : `${n} DA`
}

export function formatDateTime(iso: string | null | undefined, locale = 'fr'): string {
  if (!iso) return '—'
  const l = locale === 'ar' ? 'ar-DZ' : locale === 'en' ? 'en-GB' : 'fr-FR'
  return new Intl.DateTimeFormat(l, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso))
}

export function formatTime(iso: string | null | undefined, locale = 'fr'): string {
  if (!iso) return '—'
  const l = locale === 'ar' ? 'ar-DZ' : locale === 'en' ? 'en-GB' : 'fr-FR'
  return new Intl.DateTimeFormat(l, { timeStyle: 'short' }).format(new Date(iso))
}

export function todayIso(): string { return new Date().toISOString().slice(0, 10) }

export function toLocalDatetimeInput(d = new Date(Date.now() + 86_400_000)): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}
