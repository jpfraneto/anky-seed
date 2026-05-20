import type { Env } from "../env";
import { openRouterProvider } from "./providers";

export async function callOpenRouter(input: {
  env: Env;
  prompt: string;
}): Promise<string> {
  const reflection = await openRouterProvider.reflect(input);
  return JSON.stringify({ title: reflection.title, reflection: reflection.reflection });
}
