// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Served from GitHub Pages at https://vikaskumar75.github.io/flutter-shield/.
// If the repository is renamed or a custom domain is added, update `site`
// and `base` together.
export default defineConfig({
  site: 'https://vikaskumar75.github.io',
  base: '/flutter-shield',
  integrations: [
    starlight({
      title: 'device_shield',
      description:
        'Runtime device-security checks for Flutter apps: root, jailbreak, emulator, debugger and mock-location detection, plus screen capture protection.',
      logo: { src: './src/assets/logo.svg', alt: 'device_shield' },
      favicon: '/favicon.svg',
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/Vikaskumar75/flutter-shield',
        },
      ],
      editLink: {
        baseUrl: 'https://github.com/Vikaskumar75/flutter-shield/edit/main/website/',
      },
      lastUpdated: true,
      customCss: ['./src/styles/theme.css'],
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Introduction', slug: 'introduction' },
            { label: 'Installation', slug: 'installation' },
            { label: 'Quick start', slug: 'quick-start' },
          ],
        },
        {
          label: 'Platform setup',
          items: [
            { label: 'Android', slug: 'platforms/android' },
            { label: 'iOS', slug: 'platforms/ios' },
          ],
        },
        {
          label: 'Detection',
          items: [
            { label: 'Root (Android)', slug: 'detection/root' },
            { label: 'Jailbreak (iOS)', slug: 'detection/jailbreak' },
            { label: 'Emulator & simulator', slug: 'detection/emulator' },
            { label: 'Debugger', slug: 'detection/debugger' },
            { label: 'Mock location', slug: 'detection/mock-location' },
            { label: 'Screenshots', slug: 'detection/screenshot' },
            { label: 'Screen recording', slug: 'detection/screen-recording' },
          ],
        },
        {
          label: 'Protection',
          items: [
            { label: 'Screenshot protection', slug: 'protection/screenshot' },
            { label: 'App-switcher protection', slug: 'protection/app-switcher' },
          ],
        },
        {
          label: 'Concepts',
          items: [
            { label: 'Detection results', slug: 'concepts/detection-results' },
            { label: 'Security model', slug: 'concepts/security-model' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'API status', slug: 'reference/api' },
            { label: 'Signals', slug: 'reference/signals' },
            { label: 'Error codes', slug: 'reference/errors' },
            { label: 'Platform support', slug: 'reference/platform-support' },
          ],
        },
        {
          label: 'Help',
          items: [
            { label: 'Troubleshooting', slug: 'help/troubleshooting' },
            { label: 'FAQ', slug: 'help/faq' },
            {
              label: 'Changelog',
              link: 'https://github.com/Vikaskumar75/flutter-shield/blob/main/app/CHANGELOG.md',
              attrs: { target: '_blank' },
            },
            {
              label: 'Contributing',
              link: 'https://github.com/Vikaskumar75/flutter-shield/blob/main/CONTRIBUTING.md',
              attrs: { target: '_blank' },
            },
          ],
        },
      ],
    }),
  ],
});
