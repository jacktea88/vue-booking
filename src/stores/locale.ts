import { defineStore } from 'pinia'
import { ref } from 'vue'
import { applyLocale, type AppLocale, i18n } from '@/i18n'

export const useLocaleStore = defineStore('locale', () => {
  const current = ref<AppLocale>((i18n.global.locale as unknown as { value: AppLocale }).value)

  function set(locale: AppLocale): void {
    current.value = locale
    applyLocale(locale)
  }
  // apply on store creation so <html dir> is correct on first paint
  applyLocale(current.value)

  return { current, set }
})
