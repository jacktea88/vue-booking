<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ratingService } from '@/services/domain'
import { useToast } from '@/composables/useToast'
import { toAppError } from '@/types/errors'

const props = defineProps<{ bookingId: string; title: string }>()
const emit = defineEmits<{ rated: [] }>()
const { t } = useI18n()
const toast = useToast()
const rating = ref(5)
const comment = ref('')
const busy = ref(false)

async function submit() {
  busy.value = true
  try {
    await ratingService.rate(props.bookingId, rating.value, comment.value || undefined)
    toast.success(t('rating.submitted'))
    emit('rated')
  } catch (e) { toast.error(t(toAppError(e).i18nKey)) } finally { busy.value = false }
}
</script>

<template>
  <form class="card card-body rounded-3 shadow-sm" @submit.prevent="submit">
    <h2 class="fs-6 fw-semibold mb-0">{{ title }}</h2>
    <div class="mt-3 d-flex align-items-center gap-1" role="radiogroup" :aria-label="t('rating.rate')">
      <button v-for="n in 5" :key="n" type="button" class="btn btn-link p-0 text-decoration-none fs-2 lh-1"
              :class="n <= rating ? 'text-warning' : 'text-body-tertiary'"
              role="radio" :aria-checked="n === rating" :aria-label="String(n)" @click="rating = n">★</button>
    </div>
    <label class="form-label mt-3" for="comment">{{ t('rating.comment') }} ({{ t('common.optional') }})</label>
    <textarea id="comment" v-model="comment" class="form-control" rows="2" />
    <button class="btn btn-primary mt-3" type="submit" :disabled="busy">{{ t('common.submit') }}</button>
  </form>
</template>
