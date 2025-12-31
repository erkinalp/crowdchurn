import { cast } from "ts-safe-cast";

import { request, ResponseError } from "$app/utils/request";

export type Post = {
  id: string;
  name: string;
  message: string;
  published_at: string | null;
  has_ab_test: boolean;
  post_variants_count: number;
};

export type PostVariant = {
  id: string;
  name: string;
  message: string;
  is_control: boolean;
  price_cents: number | null;
  distribution_rules_count: number;
  assignments_count: number;
  comments_count: number;
};

export type DistributionRule = {
  id: number;
  post_variant_id: string;
  base_variant_id: number;
  distribution_type: "percentage" | "count" | "unlimited";
  distribution_value: number | null;
};

export type VariantAssignment = {
  id: number;
  post_variant_id: string;
  subscription_id: string;
  assigned_at: string;
};

export type PostComment = {
  id: string;
  content: string;
  author_id: string | null;
  author_name: string | null;
  parent_id: string | null;
  created_at: string;
  updated_at: string;
  variant?: {
    id: string;
    name: string;
  };
  variant_ids?: string[];
  variants?: {
    id: string;
    name: string;
  }[];
};

export type PaginationInfo = {
  next_page_key: string;
  next_page_url: string;
};

type ApiResponse<T> = {
  success: boolean;
  message?: string;
} & T;

const API_BASE = "/api/v2";

export async function getPosts(
  productId: string,
  options?: { page_key?: string },
): Promise<{ posts: Post[]; pagination?: PaginationInfo }> {
  const params = new URLSearchParams();
  if (options?.page_key) params.set("page_key", options.page_key);

  const url = `${API_BASE}/products/${productId}/posts${params.toString() ? `?${params}` : ""}`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ posts: Post[]; next_page_key?: string; next_page_url?: string }>>(
    await response.json(),
  );
  if (!json.success) throw new ResponseError(json.message);

  return {
    posts: json.posts,
    pagination:
      json.next_page_key && json.next_page_url
        ? { next_page_key: json.next_page_key, next_page_url: json.next_page_url }
        : undefined,
  };
}

export async function getPost(productId: string, postId: string): Promise<Post> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ post: Post }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.post;
}

export async function getPostVariants(productId: string, postId: string): Promise<PostVariant[]> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ post_variants: PostVariant[] }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.post_variants;
}

export async function getPostVariant(productId: string, postId: string, variantId: string): Promise<PostVariant> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ post_variant: PostVariant }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.post_variant;
}

export async function createPostVariant(
  productId: string,
  postId: string,
  data: { name: string; message: string; is_control?: boolean; price_cents?: number | null },
): Promise<PostVariant> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants`;
  const response = await request({ method: "POST", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ post_variant: PostVariant }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.post_variant;
}

export async function updatePostVariant(
  productId: string,
  postId: string,
  variantId: string,
  data: { name?: string; message?: string; is_control?: boolean; price_cents?: number | null },
): Promise<PostVariant> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}`;
  const response = await request({ method: "PUT", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ post_variant: PostVariant }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.post_variant;
}

export async function deletePostVariant(productId: string, postId: string, variantId: string): Promise<void> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}`;
  const response = await request({ method: "DELETE", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<Record<string, never>>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);
}

export async function getDistributionRules(
  productId: string,
  postId: string,
  variantId: string,
): Promise<DistributionRule[]> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}/distribution_rules`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ distribution_rules: DistributionRule[] }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.distribution_rules;
}

export async function createDistributionRule(
  productId: string,
  postId: string,
  variantId: string,
  data: { base_variant_id: number; distribution_type: string; distribution_value?: number },
): Promise<DistributionRule> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}/distribution_rules`;
  const response = await request({ method: "POST", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ distribution_rule: DistributionRule }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.distribution_rule;
}

export async function updateDistributionRule(
  productId: string,
  postId: string,
  variantId: string,
  ruleId: number,
  data: { base_variant_id?: number; distribution_type?: string; distribution_value?: number },
): Promise<DistributionRule> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}/distribution_rules/${ruleId}`;
  const response = await request({ method: "PUT", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ distribution_rule: DistributionRule }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.distribution_rule;
}

export async function deleteDistributionRule(
  productId: string,
  postId: string,
  variantId: string,
  ruleId: number,
): Promise<void> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}/distribution_rules/${ruleId}`;
  const response = await request({ method: "DELETE", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<Record<string, never>>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);
}

export async function getVariantAssignments(
  productId: string,
  postId: string,
  variantId: string,
  options?: { page_key?: string },
): Promise<{ assignments: VariantAssignment[]; pagination?: PaginationInfo }> {
  const params = new URLSearchParams();
  if (options?.page_key) params.set("page_key", options.page_key);

  const url = `${API_BASE}/products/${productId}/posts/${postId}/post_variants/${variantId}/assignments${params.toString() ? `?${params}` : ""}`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<
    ApiResponse<{ variant_assignments: VariantAssignment[]; next_page_key?: string; next_page_url?: string }>
  >(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return {
    assignments: json.variant_assignments,
    pagination:
      json.next_page_key && json.next_page_url
        ? { next_page_key: json.next_page_key, next_page_url: json.next_page_url }
        : undefined,
  };
}

export async function getPostComments(
  productId: string,
  postId: string,
  options?: { variant_id?: string; page_key?: string },
): Promise<{ comments: PostComment[]; pagination?: PaginationInfo }> {
  const params = new URLSearchParams();
  if (options?.variant_id) params.set("variant_id", options.variant_id);
  if (options?.page_key) params.set("page_key", options.page_key);

  const url = `${API_BASE}/products/${productId}/posts/${postId}/comments${params.toString() ? `?${params}` : ""}`;
  const response = await request({ method: "GET", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ comments: PostComment[]; next_page_key?: string; next_page_url?: string }>>(
    await response.json(),
  );
  if (!json.success) throw new ResponseError(json.message);

  return {
    comments: json.comments,
    pagination:
      json.next_page_key && json.next_page_url
        ? { next_page_key: json.next_page_key, next_page_url: json.next_page_url }
        : undefined,
  };
}

export async function createPostComment(
  productId: string,
  postId: string,
  data: { content: string; parent_id?: string; variant_id?: string; variant_ids?: string[] },
): Promise<PostComment> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/comments`;
  const response = await request({ method: "POST", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ comment: PostComment }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.comment;
}

export async function updatePostComment(
  productId: string,
  postId: string,
  commentId: string,
  data: { content: string },
): Promise<PostComment> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/comments/${commentId}`;
  const response = await request({ method: "PUT", accept: "json", url, data });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<{ comment: PostComment }>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);

  return json.comment;
}

export async function deletePostComment(productId: string, postId: string, commentId: string): Promise<void> {
  const url = `${API_BASE}/products/${productId}/posts/${postId}/comments/${commentId}`;
  const response = await request({ method: "DELETE", accept: "json", url });

  if (!response.ok) throw new ResponseError();
  const json = cast<ApiResponse<Record<string, never>>>(await response.json());
  if (!json.success) throw new ResponseError(json.message);
}
