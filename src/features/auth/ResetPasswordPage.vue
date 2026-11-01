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
  <section class="card card-body mt-4 rounded-3 shadow-sm">
    <h1 class="fs-4 fw-bold">{{ t('auth.newPassword') }}</h1>
    <form class="d-flex flex-column gap-3 mt-3" @submit.prevent="submit">
      <input v-model="password" class="form-control" type="password" minlength="8" required :aria-label="t('auth.newPassword')" />
      <p v-if="error" class="small text-danger mb-0" role="alert">{{ error }}</p>
      <p v-if="done" class="small text-success mb-0">{{ t('auth.passwordUpdated') }}</p>
      <button class="btn btn-primary w-100" type="submit">{{ t('common.save') }}</button>
    </form>
  </section>
</template>
