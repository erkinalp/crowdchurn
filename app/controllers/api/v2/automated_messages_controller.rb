# frozen_string_literal: true

module Api
  module V2
    class AutomatedMessagesController < ApiController
      before_action :authenticate_api_user!
      before_action :set_message, only: [:show, :reply]

      # GET /api/v2/automated_messages
      # Get inbox messages (received or sent)
      def index
        if params[:type] == 'sent'
          # Messages sent by seller
          @messages = AutomatedMessage
                       .for_creator(current_api_user)
                       .includes(:user, :message_template)
                       .order(sent_at: :desc)
                       .page(params[:page])
        else
          # Messages received by buyer
          @messages = AutomatedMessage
                       .for_inbox(current_api_user)
                       .includes(:sender, :message_template)
                       .order(sent_at: :desc)
                       .page(params[:page])
        end

        render json: {
          messages: @messages.map { |m| message_json(m) },
          meta: pagination_meta(@messages)
        }
      end

      # GET /api/v2/automated_messages/:id
      def show
        unless @message.user == current_api_user || @message.sender == current_api_user
          render json: { error: 'Unauthorized' }, status: :forbidden
          return
        end

        # Mark as read if buyer is viewing
        @message.mark_as_read! if @message.user == current_api_user

        render json: {
          message: message_json(@message, include_thread: true)
        }
      end

      # POST /api/v2/automated_messages/:id/reply
      def reply
        unless @message.can_reply?(current_api_user)
          render json: { error: 'Cannot reply to this message' }, status: :forbidden
          return
        end

        reply_obj = @message.automated_message_replies.build(
          sender: current_api_user,
          recipient: @message.sender,
          message_body: params[:message_body]
        )

        if reply_obj.save
          render json: {
            reply: reply_json(reply_obj),
            message: 'Reply sent successfully'
          }, status: :created
        else
          render json: { errors: reply_obj.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v2/automated_messages/send
      # Manually trigger a message (for testing/debugging)
      def send_message
        template = current_api_user.message_templates.find_by!(external_id: params[:template_id])
        purchase = current_api_user.sales.find_by!(external_id: params[:purchase_id])

        # Use trigger service to send
        MessageTriggerService.new(purchase).send(:send_message, template)

        render json: { message: 'Message queued for sending' }, status: :accepted
      end

      private

      def set_message
        @message = AutomatedMessage.find_by!(external_id: params[:id])
      end

      def message_json(message, include_thread: false)
        data = {
          id: message.external_id,
          sender_id: message.sender.external_id,
          sender_name: message.sender.name,
          recipient_id: message.user.external_id,
          recipient_name: message.user.name || message.user.email,
          subject: message.rendered_subject,
          message: message.rendered_message,
          sent_at: message.sent_at,
          read_at: message.read_at,
          buyer_replied: message.buyer_replied,
          template_id: message.message_template.external_id,
          template_name: message.message_template.name
        }

        if include_thread
          data[:thread] = message.conversation_thread.map { |r| reply_json(r) }
        end

        data
      end

      def reply_json(reply)
        {
          id: reply.id,
          sender_id: reply.sender.external_id,
          sender_name: reply.sender.name,
          recipient_id: reply.recipient.external_id,
          message_body: reply.message_body,
          created_at: reply.created_at,
          read_at: reply.read_at
        }
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
