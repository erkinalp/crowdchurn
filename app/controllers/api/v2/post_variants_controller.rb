# frozen_string_literal: true

class Api::V2::PostVariantsController < Api::V2::BaseController
  before_action(only: [:index, :show, :metrics]) { doorkeeper_authorize!(*Doorkeeper.configuration.public_scopes.concat([:view_public])) }
  before_action(only: [:create, :update, :destroy]) { doorkeeper_authorize! :edit_products }
  before_action :fetch_product
  before_action :fetch_post
  before_action :fetch_post_variant, only: [:show, :update, :destroy]

  def index
    success_with_object(:post_variants, @post.post_variants.map { |v| post_variant_json(v) })
  end

  def metrics
    variants_metrics = @post.post_variants.map do |variant|
      assignments = variant.variant_assignments
      exposure_count = assignments.exposed.count
      conversion_count = assignments.converted.count
      conversion_rate = exposure_count > 0 ? (conversion_count.to_f / exposure_count * 100).round(2) : 0.0

      {
        id: variant.external_id,
        name: variant.name,
        is_control: variant.is_control,
        price_cents: variant.price_cents,
        assignments_count: assignments.count,
        exposure_count: exposure_count,
        conversion_count: conversion_count,
        conversion_rate: conversion_rate
      }
    end

    total_exposures = variants_metrics.sum { |v| v[:exposure_count] }
    total_conversions = variants_metrics.sum { |v| v[:conversion_count] }
    overall_conversion_rate = total_exposures > 0 ? (total_conversions.to_f / total_exposures * 100).round(2) : 0.0

    success_with_object(:metrics, {
                          post_id: @post.external_id,
                          variants: variants_metrics,
                          totals: {
                            exposure_count: total_exposures,
                            conversion_count: total_conversions,
                            conversion_rate: overall_conversion_rate
                          }
                        })
  end

  def create
    post_variant = @post.post_variants.new(permitted_params)
    if post_variant.save
      success_with_post_variant(post_variant)
    else
      error_with_creating_object(:post_variant, post_variant)
    end
  end

  def show
    success_with_post_variant(@post_variant)
  end

  def update
    if @post_variant.update(permitted_params)
      success_with_post_variant(@post_variant)
    else
      error_with_post_variant(@post_variant)
    end
  end

  def destroy
    if @post_variant.destroy
      success_with_post_variant
    else
      error_with_post_variant(@post_variant)
    end
  end

  private
    def permitted_params
      params.permit(:name, :message, :is_control, :price_cents)
    end

    def fetch_post
      @post = @product.installments.alive.find_by_external_id(params[:post_id])
      error_with_object(:post, nil) if @post.nil?
    end

    def fetch_post_variant
      @post_variant = @post.post_variants.find_by_external_id(params[:id])
      error_with_post_variant if @post_variant.nil?
    end

    def post_variant_json(post_variant)
      {
        id: post_variant.external_id,
        name: post_variant.name,
        message: post_variant.message,
        is_control: post_variant.is_control,
        price_cents: post_variant.price_cents,
        distribution_rules_count: post_variant.variant_distribution_rules.count,
        assignments_count: post_variant.variant_assignments.count,
        comments_count: post_variant.comments.count
      }
    end

    def success_with_post_variant(post_variant = nil)
      success_with_object(:post_variant, post_variant.present? ? post_variant_json(post_variant) : nil)
    end

    def error_with_post_variant(post_variant = nil)
      error_with_object(:post_variant, post_variant)
    end
end
