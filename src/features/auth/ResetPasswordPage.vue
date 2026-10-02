<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { toAppError } from '@/types/errors'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const password = ref('')
const error = ref<string | null>(null)
const done = ref(false)

async function submit() {
  error.value = null
  try { await auth.updatePassword(password.value); done.value = true; setTimeout(() => router.push({ name: 'home' }), 1200) }
  catch (e) { error.value = t(toAppError(e).i18nKey) }
}
</script>

<template>
  <section class="card mt-6">
    <h1 class="text-xl font-bold">{{ t('auth.newPassword') }}</h1>
    <form class="mt-5 space-y-4" @submit.prevent="submit">
      <input v-model="password" class="field" type="password" minlength="8" required :aria-label="t('auth.newPassword')" />
      <p v-if="error" class="text-sm text-red-700" role="alert">{{ error }}</p>
      <p v-if="done" class="text-sm text-emerald-700">{{ t('auth.passwordUpdated') }}</p>
      <button class="btn-primary w-full" type="submit">{{ t('common.save') }}</button>
    </form>
  </section>
</template>
