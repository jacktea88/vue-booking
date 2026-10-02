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
  <form class="card" @submit.prevent="submit">
    <h2 class="text-sm font-semibold text-slate-700">{{ title }}</h2>
    <div class="mt-3 flex items-center gap-1" role="radiogroup" :aria-label="t('rating.rate')">
      <button v-for="n in 5" :key="n" type="button" class="text-2xl leading-none"
              :class="n <= rating ? 'text-amber-500' : 'text-slate-300'"
              role="radio" :aria-checked="n === rating" :aria-label="String(n)" @click="rating = n">★</button>
    </div>
    <label class="label mt-3" for="comment">{{ t('rating.comment') }} ({{ t('common.optional') }})</label>
    <textarea id="comment" v-model="comment" class="field" rows="2" />
    <button class="btn-primary mt-3" type="submit" :disabled="busy">{{ t('common.submit') }}</button>
  </form>
</template>
