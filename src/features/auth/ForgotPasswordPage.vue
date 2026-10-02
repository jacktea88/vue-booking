<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { RouterLink } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { toAppError } from '@/types/errors'

const { t } = useI18n()
const auth = useAuthStore()
const email = ref('')
const sent = ref(false)
const error = ref<string | null>(null)

async function submit() {
  error.value = null
  try { await auth.requestPasswordReset(email.value); sent.value = true }
  catch (e) { error.value = t(toAppError(e).i18nKey) }
}
</script>

<template>
  <section class="card mt-6">
    <h1 class="text-xl font-bold">{{ t('auth.reset') }}</h1>
    <form v-if="!sent" class="mt-5 space-y-4" @submit.prevent="submit">
      <div>
        <label class="label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="field" type="email" required />
      </div>
      <p v-if="error" class="text-sm text-red-700" role="alert">{{ error }}</p>
      <button class="btn-primary w-full" type="submit">{{ t('common.submit') }}</button>
    </form>
    <p v-else class="mt-4 text-sm text-emerald-700">{{ t('auth.resetSent') }}</p>
    <RouterLink class="mt-4 inline-block text-sm text-brand-700 hover:underline" :to="{ name: 'login' }">
      {{ t('common.back') }}
    </RouterLink>
  </section>
</template>
