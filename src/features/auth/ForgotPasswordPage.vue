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
  <section class="card card-body mt-4 rounded-3 shadow-sm">
    <h1 class="fs-4 fw-bold">{{ t('auth.reset') }}</h1>
    <form v-if="!sent" class="d-flex flex-column gap-3 mt-3" @submit.prevent="submit">
      <div>
        <label class="form-label" for="email">{{ t('auth.email') }}</label>
        <input id="email" v-model="email" class="form-control" type="email" required />
      </div>
      <p v-if="error" class="small text-danger mb-0" role="alert">{{ error }}</p>
      <button class="btn btn-primary w-100" type="submit">{{ t('common.submit') }}</button>
    </form>
    <p v-else class="mt-3 small text-success">{{ t('auth.resetSent') }}</p>
    <RouterLink class="mt-3 d-inline-block small text-primary" :to="{ name: 'login' }">
      {{ t('common.back') }}
    </RouterLink>
  </section>
</template>
