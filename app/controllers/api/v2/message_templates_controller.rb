# frozen_string_literal: true

module Api
  module V2
    class MessageTemplatesController < ApiController
      before_action :authenticate_api_user!
      before_action :set_template, only: [:show, :update, :destroy, :analytics]
      before_action :authorize_template, only: [:show, :update, :destroy, :analytics]

      # GET /api/v2/message_templates
      def index
        @templates = current_api_user.message_templates
                                     .alive
                                     .includes(:message_template_variants)
                                     .order(created_at: :desc)
                                     .page(params[:page])

        render json: {
          templates: @templates.map { |t| template_json(t) },
          meta: pagination_meta(@templates)
        }
      end

      # GET /api/v2/message_templates/:id
      def show
        render json: { template: template_json(@template, include_variants: true) }
      end

      # POST /api/v2/message_templates
      def create
        templateable = find_templateable
        return unless templateable

        @template = templateable.message_templates.build(template_params)
        @template.user = current_api_user

        if @template.save
          render json: { template: template_json(@template, include_variants: true) }, status: :created
        else
          render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v2/message_templates/:id
      def update
        if @template.update(template_params)
          render json: { template: template_json(@template, include_variants: true) }
        else
          render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v2/message_templates/:id
      def destroy
        @template.update(deleted_at: Time.current)
        head :no_content
      end

      # GET /api/v2/message_templates/:id/analytics
      def analytics
        stats = MessageTemplateAnalyticsService.new(@template).call

        render json: {
          template_id: @template.external_id,
          analytics: stats
        }
      end

      # POST /api/v2/message_templates/:id/preview
      # Preview rendered message for a specific purchase
      def preview
        set_template
        authorize_template

        purchase = current_api_user.sales.find_by!(external_id: params[:purchase_id])
        variant = @template.select_variant || @template
        rendered = MessageRenderingService.new(variant, purchase).call

        render json: {
          template_id: @template.external_id,
          variant_used: variant.is_a?(MessageTemplateVariant) ? variant.variant_name : 'main',
          rendered_subject: rendered[:subject],
          rendered_body: rendered[:body]
        }
      end

      private

      def set_template
        @template = MessageTemplate.alive.find_by!(external_id: params[:id])
      end

      def authorize_template
        unless @template.user == current_api_user
          render json: { error: 'Unauthorized' }, status: :forbidden
        end
      end

      def find_templateable
        if params[:link_id]
          current_api_user.links.find_by!(external_id: params[:link_id])
        elsif params[:installment_id]
          current_api_user.installments.find_by!(external_id: params[:installment_id])
        else
          render json: { error: 'Must specify link_id or installment_id' }, status: :bad_request
          nil
        end
      end

      def template_params
        params.require(:message_template).permit(
          :name, :message_body, :subject, :trigger_type, :active, :priority,
          trigger_config: {},
          message_template_variants_attributes: [
            :id, :variant_name, :message_body, :subject, :weight, :_destroy
          ]
        )
      end

      def template_json(template, include_variants: false)
        data = {
          id: template.external_id,
          name: template.name,
          message_body: template.message_body,
          subject: template.subject,
          trigger_type: template.trigger_type,
          trigger_config: template.trigger_config,
          active: template.active,
          priority: template.priority,
          created_at: template.created_at,
          updated_at: template.updated_at,
          available_variables: MessageTemplate::VARIABLES
        }

        if include_variants
          data[:variants] = template.message_template_variants.map do |variant|
            {
              id: variant.id,
              variant_name: variant.variant_name,
              message_body: variant.message_body,
              subject: variant.subject,
              weight: variant.weight,
              sent_count: variant.sent_count,
              read_count: variant.read_count,
              reply_count: variant.reply_count,
              read_rate: variant.read_rate,
              reply_rate: variant.reply_rate
            }
          end
        end

        data
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end
    end
  end
end
