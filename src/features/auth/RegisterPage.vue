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
  <section class="card card-body mt-4 rounded-3 shadow-sm">
    <h1 class="fs-4 fw-bold">{{ t('auth.register') }}</h1>
    <form class="d-flex flex-column gap-3 mt-3" @submit.prevent="submit">
      <div>
        <label class="form-label" for="name">{{ t('auth.fullName') }}</label>
        <input id="name" v-model="fullName" class="form-control" required autocomplete="name" />
      </div>
      <div>
        <label class="form-label" for="phone">{{ t('auth.phone') }}</label>
        <input id="phone" v-model="phone" class="form-control" type="tel" autocomplete="tel" placeholder="+213…" />
      </div>
      <div>
        <label class="form-label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="form-control" type="email" required autocomplete="email" />
      </div>
      <div>
        <label class="form-label" for="password">{{ t('auth.password') }}</label>
        <input id="password" v-model="password" class="form-control" type="password" required minlength="8" autocomplete="new-password" />
      </div>
      <fieldset>
        <legend class="form-label">{{ t('auth.role') }}</legend>
        <div class="row g-2">
          <div class="col-sm-6">
            <label class="d-flex align-items-center gap-2 rounded-3 border p-3 small mb-0"
                   :class="role === 'client' ? 'border-primary bg-brand-light' : ''" style="cursor: pointer">
              <input v-model="role" type="radio" value="client" class="form-check-input mt-0" />{{ t('auth.asClient') }}
            </label>
          </div>
          <div class="col-sm-6">
            <label class="d-flex align-items-center gap-2 rounded-3 border p-3 small mb-0"
                   :class="role === 'driver' ? 'border-primary bg-brand-light' : ''" style="cursor: pointer">
              <input v-model="role" type="radio" value="driver" class="form-check-input mt-0" />{{ t('auth.asDriver') }}
            </label>
          </div>
        </div>
      </fieldset>
      <p v-if="error" class="small text-danger mb-0" role="alert">{{ error }}</p>
      <button class="btn btn-primary w-100" :disabled="auth.loading" type="submit">{{ t('auth.register') }}</button>
    </form>
    <p class="mt-3 small mb-0">
      {{ t('auth.hasAccount') }}
      <RouterLink class="text-primary" :to="{ name: 'login' }">{{ t('auth.login') }}</RouterLink>
    </p>
  </section>
</template>
