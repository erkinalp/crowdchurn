# frozen_string_literal: true

class Admin::Products::PurchasesController < Admin::Products::BaseController
  include Pagy::Backend

  def index
    pagination, purchases = pagy_countless(
      @product.sales.for_admin_listing.includes(:subscription, :price, :refunds),
      limit: params[:per_page],
      page: params[:page],
      countless_minimal: true
    )

    render json: {
      purchases: purchases.as_json(admin_review: true),
      pagination:
    }
  end

  def mass_refund
    purchase_ids = mass_refund_purchase_ids

    if purchase_ids.empty?
      render json: { success: false, message: "Select at least one purchase." }, status: :unprocessable_entity
      return
    end

    purchases_relation = @product.sales.where(id: purchase_ids)
    found_ids = purchases_relation.pluck(:id)
    missing_ids = purchase_ids - found_ids

    if missing_ids.any?
      render json: { success: false, message: "Some purchases are invalid for this product." }, status: :unprocessable_entity
      return
    end

    batch = MassRefundBatch.create!(
      product: @product,
      admin_user: current_user,
      purchase_ids: purchase_ids
    )

    MassRefundPurchasesWorker.perform_async(batch.id)

    render json: {
      success: true,
      message: "Mass refund started. Processing #{purchase_ids.size} purchases...",
      batch_id: batch.id
    }
  end

  def mass_refund_batch
    batch = @product.mass_refund_batches.find(params[:id])

    render json: {
      id: batch.id,
      status: batch.status,
      total_count: batch.total_count,
      processed_count: batch.processed_count,
      refunded_count: batch.refunded_count,
      blocked_count: batch.blocked_count,
      failed_count: batch.failed_count,
      errors_by_purchase_id: batch.errors_by_purchase_id,
      error_message: batch.error_message,
      started_at: batch.started_at,
      completed_at: batch.completed_at,
      created_at: batch.created_at
    }
  end

  private
    def mass_refund_purchase_ids
      raw_ids = params[:purchase_ids]
      values =
        case raw_ids
        when String
          raw_ids.split(",")
        else
          Array(raw_ids)
        end
      values.map(&:to_i).reject(&:zero?).uniq
    end
end
