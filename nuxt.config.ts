import tailwindcss from '@tailwindcss/vite'
export default defineNuxtConfig({
  ssr: false,
  devtools: { enabled: false },
  runtimeConfig: { public: { supabaseUrl: '', supabaseKey: '' } },
  vite: { plugins: [tailwindcss()] },
  app: { head: { title: 'Ruang CPNS', htmlAttrs: { lang: 'id' } } }
})
