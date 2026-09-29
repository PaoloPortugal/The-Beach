// postject ships no types; this is the part of its API scripts/package.ts uses.
declare module 'postject' {
  export function inject(
    filename: string,
    resourceName: string,
    resourceData: Buffer,
    options?: { sentinelFuse?: string; machoSegmentName?: string; overwrite?: boolean },
  ): Promise<void>
}
