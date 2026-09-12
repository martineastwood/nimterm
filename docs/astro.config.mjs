// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightThemeBlack from 'starlight-theme-black';

export default defineConfig({
	site: 'https://nimterm.niminal.dev',
	integrations: [
		starlight({
			title: 'nimterm',
			description: 'Terminal UI primitives for Nim applications and agent frontends.',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/martineastwood/nimterm' }],
			plugins: [
				starlightThemeBlack({
					navLinks: [{ label: 'Niminal', link: 'https://niminal.dev' }],
					docs: { showMarkdownActions: false },
				}),
			],
		}),
	],
});
