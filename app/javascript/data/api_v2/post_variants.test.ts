import { beforeEach, describe, expect, it, vi } from "vitest";

import { getPostComments, getPosts, getPostVariants } from "$app/data/api_v2/post_variants";
import { request, ResponseError } from "$app/utils/request";

vi.mock("$app/utils/request", async (importOriginal) => ({
  ...(await importOriginal<typeof import("$app/utils/request")>()),
  request: vi.fn(),
}));

const respondWith = (data: unknown) => vi.mocked(request).mockResolvedValue(new Response(JSON.stringify(data)));

beforeEach(() => vi.clearAllMocks());

describe("Post variant API response validation", () => {
  it("retains variant pricing and distribution data", async () => {
    const variant = {
      id: "variant-id",
      name: "Experiment treatment",
      message: "Treatment content",
      is_control: false,
      price_cents: 1500,
      distribution_rules_count: 1,
      assignments_count: 4,
      comments_count: 2,
    };
    respondWith({ success: true, post_variants: [variant] });
    expect(await getPostVariants("product-id", "post-id")).toEqual([variant]);
  });

  it("handles a discriminated failure without expecting success payload fields", async () => {
    respondWith({ success: false, message: "Post not found" });
    await expect(getPostVariants("product-id", "missing-post")).rejects.toThrow(new ResponseError("Post not found"));
  });

  it("omits pagination when the server has no next page", async () => {
    respondWith({ success: true, posts: [] });
    expect(await getPosts("product-id")).toEqual({ posts: [] });
  });

  it("preserves multi-variant comment targeting and pagination", async () => {
    const comment = {
      id: "comment-id",
      content: "Seller response",
      author_id: null,
      author_name: "Seller",
      parent_id: null,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z",
      variant_ids: ["variant-a", "variant-b"],
      variants: [
        { id: "variant-a", name: "A" },
        { id: "variant-b", name: "B" },
      ],
    };
    const pagination = { next_page_key: "next-page", next_page_url: "/next-page" };
    respondWith({ success: true, comments: [comment], ...pagination });
    expect(await getPostComments("product-id", "post-id", { variant_id: "variant-a" })).toEqual({
      comments: [comment],
      pagination,
    });
  });

  it("rejects malformed success payloads", async () => {
    respondWith({ success: true, post_variants: [{ id: "variant-id" }] });
    await expect(getPostVariants("product-id", "post-id")).rejects.toThrow();
  });
});
