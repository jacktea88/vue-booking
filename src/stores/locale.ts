import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { applyLocale, isRtl, type AppLocale, i18n } from '@/i18n'

export const useLocaleStore = defineStore('locale', () => {
  const current = ref<AppLocale>((i18n.global.locale as unknown as { value: AppLocale }).value)
  const rtl = computed(() => isRtl(current.value))

  function set(locale: AppLocale): void {
    current.value = locale
    applyLocale(locale)
  }
  // apply on store creation so <html dir> is correct on first paint
  applyLocale(current.value)

  return { current, rtl, set }
})
