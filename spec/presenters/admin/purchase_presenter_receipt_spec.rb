# frozen_string_literal: true

require "spec_helper"

describe Admin::PurchasePresenter, "receipt delivery status" do
  let(:purchase) { create(:purchase) }
  let(:presenter) { described_class.new(purchase.reload) }

  it "shows the delivery status of a charge-level receipt" do
    charge = create(:charge, purchases: [purchase], seller: purchase.seller)
    email_info = create(
      :customer_email_info_delivered,
      purchase_id: nil,
      email_name: SendgridEventInfo::RECEIPT_MAILER_METHOD,
      email_info_charge_attributes: { charge_id: charge.id }
    )

    expect(presenter.props[:email_info]).to eq("Delivered (on #{email_info.delivered_at})")
  end

  it "uses the latest combined receipt rather than a legacy purchase marker" do
    other_purchases = Array.new(2) { create(:purchase, seller: purchase.seller, link: purchase.link) }
    charge = create(:charge, purchases: [purchase, *other_purchases], seller: purchase.seller)
    create(:customer_email_info, purchase:, email_name: SendgridEventInfo::RECEIPT_MAILER_METHOD, state: "sent")
    email_info = create(
      :customer_email_info_delivered,
      purchase_id: nil,
      email_name: SendgridEventInfo::RECEIPT_MAILER_METHOD,
      email_info_charge_attributes: { charge_id: charge.id }
    )

    expect(presenter.props[:email_info]).to eq("Delivered (on #{email_info.delivered_at})")
  end

  it "shows the purchase receipt once a two-product charge has split receipts" do
    other_purchase = create(:purchase, seller: purchase.seller, link: purchase.link)
    charge = create(:charge, purchases: [purchase, other_purchase], seller: purchase.seller)
    create(
      :customer_email_info,
      purchase_id: nil,
      email_name: SendgridEventInfo::RECEIPT_MAILER_METHOD,
      state: "sent",
      email_info_charge_attributes: { charge_id: charge.id }
    )
    email_info = create(:customer_email_info_delivered, purchase:, email_name: SendgridEventInfo::RECEIPT_MAILER_METHOD)

    expect(presenter.props[:email_info]).to eq("Delivered (on #{email_info.delivered_at})")
  end
end
