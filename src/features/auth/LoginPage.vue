<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { toAppError } from '@/types/errors'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref<string | null>(null)

async function submit() {
  error.value = null
  try {
    await auth.signIn(email.value, password.value)
    const redirect = (route.query.redirect as string) || null
    if (redirect) await router.push(redirect)
    else await router.push({ name: auth.isAdmin ? 'admin' : auth.isDriver ? 'driver-home' : 'home' })
  } catch (e) { error.value = t(toAppError(e).i18nKey) }
}
</script>

<template>
  <section class="card mt-6">
    <h1 class="text-xl font-bold">{{ t('auth.login') }}</h1>
    <p class="mt-1 text-sm text-slate-500">{{ t('app.tagline') }}</p>
    <form class="mt-5 space-y-4" @submit.prevent="submit">
      <div>
        <label class="label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="field" type="email" required autocomplete="email" />
      </div>
      <div>
        <label class="label" for="password">{{ t('auth.password') }}</label>
        <input id="password" v-model="password" class="field" type="password" required autocomplete="current-password" />
      </div>
      <p v-if="error" class="text-sm text-red-700" role="alert">{{ error }}</p>
      <button class="btn-primary w-full" :disabled="auth.loading" type="submit">
        {{ auth.loading ? t('auth.signingIn') : t('auth.login') }}
      </button>
    </form>
    <div class="mt-4 flex items-center justify-between text-sm">
      <RouterLink class="text-brand-700 hover:underline" :to="{ name: 'forgot' }">{{ t('auth.forgot') }}</RouterLink>
      <RouterLink class="text-brand-700 hover:underline" :to="{ name: 'register' }">{{ t('auth.register') }}</RouterLink>
    </div>
  </section>
</template>
