// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightThemeNext from 'starlight-theme-next';

export default defineConfig({
	site: 'https://nimterm.niminal.dev',
	integrations: [
		starlight({
			title: 'nimterm',
			description: 'Terminal UI primitives for Nim applications and agent frontends.',
			customCss: ['./src/styles/sidebar.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/martineastwood/nimterm' }],
			sidebar: [
				{ label: 'Introduction', slug: 'index' },
				{
					label: 'API reference',
					collapsed: true,
					items: [{ autogenerate: { directory: 'reference/api' } }],
				},
			],
			plugins: [starlightThemeNext()],
		}),
	],
});
