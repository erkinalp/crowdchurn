# fron

module Purchase::AsJson
  # Public: Get a JSON response representing a Purchase object
  #
  # version - Supported versions
  #           1       - initial version
  #           2       - `price` is no longer `formatted_display_price`, and is now `price_cents`.
  #                   - `link_id` has been renamed to `product_id`, and now shows the `external_id`.
  #                   - `link_name` has been renamed to `product_name`
  #                   - `custom_fields` is no longer an array containing strings `"field: value"` and instead is now a proper hash.
  #                   - `variants` is no longer an string containing the list of variants `variant: selection, variant2: selection2` and instead is now a proper hash.
  #           default - version 1
  #                   - changes made for later versions that do not change fields in previous versions may be included
  #
  # Returns a JSON representation of the Purchase
  def as_json(options = {})
    version = options[:version] || 1
    return super(options) if options.delete(:original)
    return as_json_for_admin if options[:admin]
    return as_json_for_admin_review if options[:admin_review]

    pundit_user = options[:pundit_user]
    json = {
      id: ObfuscateIds.encrypt(id),
      email: purchaser_email_or_email,
      seller_id: ObfuscateIds.encrypt(seller.id),
      timestamp: "#{time_ago_in_words(created_at)} ago",
      daystamp: created_at.in_time_zone(seller.timezone).to_fs(:long_formatted_datetime),
      created_at:,
      link_name: (link.name if version == 1),
      product_name: link.name,
      product_has_variants: (link.association_cached?(:variant_categories_alive) ? !link.variant_categories_alive.empty? : link.variant_categories_alive.exists?),
      price: version == 1 ? formatted_display_price : price_cents,
      gumroad_fee: fee_cents,
      is_bundle_purchase:,
      is_bundle_product_purchase:,
    }

    return json.merge!(additional_fields_for_creator_app_api) if options[:creator_app_api]

    if options[:include_variant_details]
      variants_for_json = variant_details_hash
    elsif version == 1
      variants_for_json = variants_list
    else
      variants_for_json = variant_names_hash
    end

    json.merge!(
      subscription_duration:,
      formatted_display_price:,
      transaction_url_for_seller:,
      formatted_total_price:,
      currency_symbol: symbol_for(displayed_price_currency_type),
      amount_refundable_in_currency:,
      link_id: (link.unique_permalink if version == 1),
      product_id: link.external_id,
      product_permalink: link.unique_permalink,
      refunded: stripe_refunded,
      partially_refunded: stripe_partially_refunded,
      chargedback: chargedback_not_reversed?,
      purchase_email: email,
      giftee_email:,
      gifter_email:,
      full_name: full_name.try(:strip).presence || purchaser&.name,
      street_address:,
      city:,
      state: state_or_from_ip_address,
      zip_code:,
      country: country_or_from_ip_address,
      country_iso2: Compliance::Countries.find_by_name(country)&.alpha2,
      paid: price_cents != 0,
      has_variants: !variant_names_hash.nil?,
      variants: variants_for_json,
      variants_and_quantity:,
      has_custom_fields: custom_fields.present?,
      custom_fields: version == 1 ?
        custom_fields.map { |field| "#{field[:name]}: #{field[:value]}" } :
        custom_fields.pluck(:name, :value).to_h,
      order_id: external_id_numeric,
      is_product_physical: link.is_physical,
      purchaser_id: purchaser.try(:external_id),
      is_recurring_billing: link.is_recurring_billing,
      can_contact: can_contact?,
      is_following: is_following?,
      disputed: chargedback?,
      dispute_won: chargeback_reversed?,
      is_additional_contribution:,
      discover_fee_charged: was_discover_fee_charged?,
      is_upgrade_purchase: is_upgrade_purchase?,
      ppp: ppp_info,
      is_more_like_this_recommended: recommended_by == RecommendationType::GUMROAD_MORE_LIKE_THIS_RECOMMENDATION,
      is_gift_sender_purchase:,
      is_gift_receiver_purchase:,
      referrer:,
      can_revoke_access: pundit_user ? Pundit.policy!(pundit_user, [:audience, self]).revoke_access? : nil,
      can_undo_revoke_access: pundit_user ? Pundit.policy!(pundit_user, [:audience, self]).undo_revoke_access? : nil,
      can_update: pundit_user ? Pundit.policy!(pundit_user, [:audience, self]).update? : nil,
      upsell: upsell_purchase&.as_json,
      paypal_refund_expired: paypal_refund_expired?
    ).delete_if { |_, v| v.nil? }

    json[:card] = {
      visual: card_visual,
      type: card_type,

      # legacy params
      bin: nil,
      expiry_month: nil,
      expiry_year: nil
    }

    if options[:query] && options[:query].to_s == card_visual && EmailFormatValidator.valid?(card_visual)
      json[:paypal_email] = card_visual
    end

    json[:product_rating] = original_product_review.try(:rating)
    if display_product_reviews?
      json[:reviews_count] = link.reviews_count
      json[:average_rating] = link.average_rating
    end

    if subscription.present?
      json.merge!(subscription_id: subscription.external_id,
                  cancelled: subscription.cancelled_or_failed?,
                  dead: !subscription.alive?,
                  ended: subscription.ended?,
                  free_trial_ended: subscription.free_trial_ended?,
                  free_trial_ends_on: subscription.free_trial_ends_at&.to_fs(:formatted_date_abbrev_month),
                  recurring_charge: !is_original_subscription_purchase?)
    end

    if preorder.present?
      json.merge!(preorder_cancelled: preorder.is_cancelled?,
                  is_preorder_authorization:,
                  is_in_preorder_state: link.is_in_preorder_state)
    end

    if shipment.present?
      json[:shipped] = shipment.shipped?
      json[:tracking_url] = shipment.calculated_tracking_url
    end

    if offer_code.present?
      json[:offer_code] = {
        code: offer_code.code,
        displayed_amount_off: offer_code.displayed_amount_off(link.price_currency_type, with_symbol: true)
      }
      # For backwards compatibility: offer code's `name` has been renamed to `code`
      json[:offer_code][:name] = offer_code.code if version <= 2
    end

    if affiliate.present?
      json[:affiliate] = {
        email: affiliate.affiliate_user.form_email,
        amount: Money.new(affiliate_credit_cents).format(no_cents_if_whole: true, symbol: true)
      }
    end

    if was_discover_fee_charged?
      json[:discover_fee_percentage] = discover_fee_per_thousand / 10
    end

    json[:receipt_url] = receipt_url if options[:include_receipt_url]

    if options[:include_ping]
      cached_value = options[:include_ping][:value] if options[:include_ping].is_a? Hash
      json[:can_ping] = cached_value != nil ? cached_value : seller.urls_for_ping_notification(ResourceSubscription::SALE_RESOURCE_NAME).size > 0
    end

    json.merge!(license_json)

    json[:sku_id] = sku.custom_name_or_external_id if sku.present?
    json[:sku_external_id] = sku.external_id if sku.present?
    json[:formatted_shipping_amount] = formatted_shipping_amount if shipping_cents > 0
    json[:quantity] = quantity
    json[:message] = messages.unread.last if options[:unread_message]
    json
  end

  def receipt_url
    Rails.application.routes.url_helpers.receipt_purchase_url(external_id, email: email, host: "#{PROTOCOL}://#{DOMAIN}")
  end

  def as_json_for_license
    json = as_json
    json[:product_name] = json.delete :link_name
    json[:email] = json.delete :purchase_email
    if link.is_recurring_billing
      json[:subscription_ended_at] = subscription.ended_at
      json[:subscription_cancelled_at] = subscription.cancelled_at
      json[:subscription_failed_at] = subscription.failed_at
    else
      json[:chargebacked] = chargedback_not_reversed?
      json[:refunded] = stripe_refunded == true
    end
    json
  end

  def as_json_for_ifttt
    json = {
      meta: {
        id: external_id,
        timestamp: created_at.to_i
      },
      Price: formatted_total_price,
      ProductName: link.name,
      PurchaseEmail: purchaser.try(:email) || email,
      ProductDescription: link.plaintext_description,
      ProductURL: link.long_url
    }

    json[:ProductImageURL] = link.preview_url if link.preview_image_path?

    json
  end

  def as_json_for_admin
    as_json(
      original: true,
      only: [
        :id,
        :email,
        :formatted_display_price,
        :formatted_gumroad_tax_amount,
        :link,
      ],
      include: {
        link: {
          original: true,
          only: [:id, :long_url, :name]
        },
        seller: {
          original: true,
          only: [:email]
        }
      },
      methods: [
        :variants_list,
        :purchase_states,
        :purchase_refund_policy,
        :formatted_error_code,
        :purchase_state,
      ]
    ).merge!(
      failed: failed?,
      error_code: error_code,
      stripe_refunded: stripe_refunded,
      stripe_partially_refunded: stripe_partially_refunded,
      chargedback_not_reversed: chargedback_not_reversed?,
      chargeback_reversed: chargeback_reversed?,
    )
  end

  def as_json_for_admin_review
    refunding_users = refunds.map(&:user).compact
    {
      "email" => email,
      "created" => "#{time_ago_in_words(created_at)} ago",
      "id" => id,
      "amount" => price_cents,
      "displayed_price" => formatted_total_price,
      "formatted_gumroad_tax_amount" => formatted_gumroad_tax_amount,
      "is_preorder_authorization" => is_preorder_authorization,
      "stripe_refunded" => stripe_refunded,
      "is_chargedback" => chargedback?,
      "is_chargeback_reversed" => chargeback_reversed,
      "refunded_by" => refunding_users.map { |u| { id: u.id, email: u.email } },
      "error_code" => error_code,
      "purchase_state" => purchase_state,
      "gumroad_responsible_for_tax" => gumroad_responsible_for_tax?
    }
  end
end
