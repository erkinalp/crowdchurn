# frozen_string_literal: true

class AutomatedMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_automated_message, only: [:show, :reply]

  def index
    # Buyer's inbox - messages received
    @received_messages = AutomatedMessage
                          .for_inbox(current_user)
                          .includes(:sender, :message_template)
                          .page(params[:page])

    # Seller's sent messages (if they want to see what was sent)
    @sent_messages = AutomatedMessage
                      .for_creator(current_user)
                      .includes(:user, :message_template)
                      .page(params[:page]) if current_user.links.any?
  end

  def show
    unless @message.user == current_user || @message.sender == current_user
      redirect_to root_path, alert: 'Not authorized'
      return
    end

    # Mark as read if buyer is viewing
    @message.mark_as_read! if @message.user == current_user

    # Load conversation thread
    @replies = @message.conversation_thread
  end

  def reply
    unless @message.can_reply?(current_user)
      redirect_to automated_message_path(@message),
                  alert: 'Cannot reply to this message'
      return
    end

    reply = @message.automated_message_replies.build(reply_params)
    reply.sender = current_user
    reply.recipient = @message.sender

    if reply.save
      redirect_to automated_message_path(@message),
                  notice: 'Reply sent successfully'
    else
      redirect_to automated_message_path(@message),
                  alert: reply.errors.full_messages.join(', ')
    end
  end

  private

  def set_automated_message
    @message = AutomatedMessage.find_by!(external_id: params[:id])
  end

  def reply_params
    params.require(:automated_message_reply).permit(:message_body)
  end
end
