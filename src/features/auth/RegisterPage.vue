<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '@/stores/auth'
import { toAppError } from '@/types/errors'

const { t } = useI18n()
const auth = useAuthStore()
const router = useRouter()

const fullName = ref('')
const phone = ref('')
const email = ref('')
const password = ref('')
/** Only client|driver can be requested — `admin` is never self-assignable. */
const role = ref<'client' | 'driver'>('client')
const error = ref<string | null>(null)

async function submit() {
  error.value = null
  try {
    await auth.signUp(email.value, password.value, fullName.value, phone.value, role.value)
    await router.push({ name: role.value === 'driver' ? 'driver-home' : 'home' })
  } catch (e) { error.value = t(toAppError(e).i18nKey) }
}
</script>

<template>
  <section class="card mt-6">
    <h1 class="text-xl font-bold">{{ t('auth.register') }}</h1>
    <form class="mt-5 space-y-4" @submit.prevent="submit">
      <div>
        <label class="label" for="name">{{ t('auth.fullName') }}</label>
        <input id="name" v-model="fullName" class="field" required autocomplete="name" />
      </div>
      <div>
        <label class="label" for="phone">{{ t('auth.phone') }}</label>
        <input id="phone" v-model="phone" class="field" type="tel" autocomplete="tel" placeholder="+213…" />
      </div>
      <div>
        <label class="label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="field" type="email" required autocomplete="email" />
      </div>
      <div>
        <label class="label" for="password">{{ t('auth.password') }}</label>
        <input id="password" v-model="password" class="field" type="password" required minlength="8" autocomplete="new-password" />
      </div>
      <fieldset>
        <legend class="label">{{ t('auth.role') }}</legend>
        <div class="grid gap-2 sm:grid-cols-2">
          <label class="flex cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm"
                 :class="role === 'client' ? 'border-brand-600 bg-brand-50' : 'border-slate-300'">
            <input v-model="role" type="radio" value="client" class="accent-teal-700" />{{ t('auth.asClient') }}
          </label>
          <label class="flex cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm"
                 :class="role === 'driver' ? 'border-brand-600 bg-brand-50' : 'border-slate-300'">
            <input v-model="role" type="radio" value="driver" class="accent-teal-700" />{{ t('auth.asDriver') }}
          </label>
        </div>
      </fieldset>
      <p v-if="error" class="text-sm text-red-700" role="alert">{{ error }}</p>
      <button class="btn-primary w-full" :disabled="auth.loading" type="submit">{{ t('auth.register') }}</button>
    </form>
    <p class="mt-4 text-sm">
      {{ t('auth.hasAccount') }}
      <RouterLink class="text-brand-700 hover:underline" :to="{ name: 'login' }">{{ t('auth.login') }}</RouterLink>
    </p>
  </section>
</template>
