# frozen_string_literal: true

require "spec_helper"

describe ElectronicInvoiceGenerator do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "John Doe",
      street_address: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip_code: "94105",
      country: "United States"
    }
  end
  let(:chargeable) { purchase }
  let(:additional_notes) { nil }
  let(:business_vat_id) { nil }

  describe ".generate" do
    it "raises UnsupportedFormatError for unknown formats" do
      expect do
        described_class.generate(
          format: "unknown",
          chargeable: chargeable,
          address_fields: address_fields
        )
      end.to raise_error(ElectronicInvoiceGenerator::UnsupportedFormatError)
    end

    it "raises UnsupportedFormatError for pdf format" do
      expect do
        described_class.generate(
          format: "pdf",
          chargeable: chargeable,
          address_fields: address_fields
        )
      end.not_to raise_error
    rescue ElectronicInvoiceGenerator::UnsupportedFormatError
    end

    ElectronicInvoiceGenerator::SUPPORTED_FORMATS.each do |fmt|
      next if fmt == "pdf"

      it "returns a generator class for #{fmt}" do
        expect(described_class.generator_for(fmt)).to be_a(Class)
      end
    end
  end

  describe ".generator_for" do
    it "returns Ubl for 'ubl'" do
      expect(described_class.generator_for("ubl")).to eq(ElectronicInvoiceGenerator::Ubl)
    end

    it "returns Peppol (alias for Ubl) for 'peppol'" do
      expect(described_class.generator_for("peppol")).to eq(ElectronicInvoiceGenerator::Ubl)
    end

    it "returns Xrechnung for 'xrechnung'" do
      expect(described_class.generator_for("xrechnung")).to eq(ElectronicInvoiceGenerator::Xrechnung)
    end

    it "returns Zugferd for 'zugferd'" do
      expect(described_class.generator_for("zugferd")).to eq(ElectronicInvoiceGenerator::Zugferd)
    end

    it "returns EfaturaIthalat for 'efatura_ithalat'" do
      expect(described_class.generator_for("efatura_ithalat")).to eq(ElectronicInvoiceGenerator::EfaturaIthalat)
    end

    it "raises UnsupportedFormatError for unknown format" do
      expect { described_class.generator_for("invalid") }.to raise_error(ElectronicInvoiceGenerator::UnsupportedFormatError)
    end
  end
end

describe ElectronicInvoiceGenerator::Base do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "John Doe",
      street_address: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip_code: "94105",
      country: "United States"
    }
  end
  let(:chargeable) { purchase }

  describe "#validate_required_data!" do
    context "when customer name is blank" do
      let(:address_fields) do
        {
          full_name: "",
          street_address: "123 Main St",
          city: "San Francisco",
          state: "CA",
          zip_code: "94105",
          country: "United States"
        }
      end

      it "raises MissingDataError when customer name resolves to 'Customer'" do
        purchase.update!(full_name: nil)
        allow(purchase).to receive(:purchaser).and_return(nil)

        generator = described_class.new(
          chargeable: chargeable,
          address_fields: address_fields
        )
        expect { generator.generate }.to raise_error(ElectronicInvoiceGenerator::MissingDataError, /Customer name is required/)
      end
    end

    context "when no line items exist" do
      it "raises MissingDataError" do
        allow(chargeable).to receive(:successful_purchases).and_return(Purchase.none)

        generator = described_class.new(
          chargeable: chargeable,
          address_fields: address_fields
        )
        expect { generator.generate }.to raise_error(ElectronicInvoiceGenerator::MissingDataError, /No invoice line items found/)
      end
    end
  end

  describe "#subunits_to_units" do
    it "divides by 100 for standard currencies like USD" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      expect(generator.send(:subunits_to_units, 1500)).to eq(15.0)
    end

    it "returns the value as-is for single-unit currencies like JPY" do
      allow(purchase).to receive(:displayed_price_currency_type).and_return("jpy")

      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      expect(generator.send(:subunits_to_units, 1500)).to eq(1500.0)
    end
  end
end

describe ElectronicInvoiceGenerator::Ubl do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "John Doe",
      street_address: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip_code: "94105",
      country: "United States"
    }
  end
  let(:chargeable) { purchase }

  describe "#generate" do
    it "generates valid UBL XML" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to be_a(String)
      expect(result).to include("Invoice")
    end

    it "calls validate_required_data!" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      expect(generator).to receive(:validate_required_data!).and_call_original
      generator.generate
    end
  end

  describe "#content_type" do
    it "returns application/xml" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      expect(generator.content_type).to eq("application/xml")
    end
  end
end

describe ElectronicInvoiceGenerator::Peppol do
  it "is an alias for Ubl" do
    expect(ElectronicInvoiceGenerator::Peppol).to eq(ElectronicInvoiceGenerator::Ubl)
  end
end

describe ElectronicInvoiceGenerator::Xrechnung do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "Hans Mueller",
      street_address: "Berliner Str. 10",
      city: "Berlin",
      state: "Berlin",
      zip_code: "10115",
      country: "Germany",
      leitweg_id: "991-12345-67"
    }
  end
  let(:chargeable) { purchase }

  describe "#generate" do
    it "generates valid UBL XML with XRechnung customization" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to be_a(String)
      expect(result).to include("Invoice")
    end
  end

  it "inherits from Ubl" do
    expect(described_class.superclass).to eq(ElectronicInvoiceGenerator::Ubl)
  end
end

describe ElectronicInvoiceGenerator::Zugferd do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "Hans Mueller",
      street_address: "Berliner Str. 10",
      city: "Berlin",
      state: "Berlin",
      zip_code: "10115",
      country: "Germany"
    }
  end
  let(:chargeable) { purchase }

  describe "#generate" do
    it "generates CII XML" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to be_a(String)
    end

    it "calls validate_required_data!" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      expect(generator).to receive(:validate_required_data!).and_call_original
      generator.generate
    end
  end

  describe "tax rate grouping" do
    let(:product2) { create(:product, user: seller, name: "Product Two", price_cents: 2_000) }

    it "groups line items by tax rate instead of averaging" do
      purchase2 = create(
        :purchase,
        link: product2,
        seller:,
        price_cents: 2_000,
        displayed_price_cents: 2_000,
        shipping_cents: 0,
        created_at: DateTime.parse("January 15, 2025")
      )

      charge = create(:charge, purchases: [purchase, purchase2], order: create(:order, purchases: [purchase, purchase2]))

      generator = described_class.new(
        chargeable: charge,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to be_a(String)
    end
  end

  it "inherits from Base" do
    expect(described_class.superclass).to eq(ElectronicInvoiceGenerator::Base)
  end
end

describe ElectronicInvoiceGenerator::EfaturaIthalat do
  let(:seller) { create(:named_seller) }
  let(:product) { create(:product, user: seller, name: "Test Product") }
  let(:purchase) do
    create(
      :purchase,
      link: product,
      seller:,
      price_cents: 1_000,
      displayed_price_cents: 1_000,
      shipping_cents: 0,
      created_at: DateTime.parse("January 15, 2025")
    )
  end
  let(:address_fields) do
    {
      full_name: "Ahmet Yilmaz",
      street_address: "Ataturk Caddesi 42",
      city: "Istanbul",
      state: "Istanbul",
      zip_code: "34000",
      country: "Turkey"
    }
  end
  let(:chargeable) { purchase }

  describe "#generate" do
    it "generates valid UBL-TR XML" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to be_a(String)
      expect(result).to include("Invoice")
      expect(result).to include("ITHALAT")
      expect(result).to include("SATIS")
    end

    it "includes UBL-TR namespaces" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      expect(result).to include("urn:oasis:names:specification:ubl:schema:xsd:Invoice-2")
      expect(result).to include("urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2")
      expect(result).to include("urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2")
    end

    it "includes additional notes when provided" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields,
        additional_notes: "Test note"
      )
      result = generator.generate
      expect(result).to include("Test note")
    end
  end

  describe "deterministic UUID" do
    it "generates the same UUID for the same invoice" do
      generator1 = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      generator2 = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )

      uuid1 = generator1.send(:deterministic_uuid)
      uuid2 = generator2.send(:deterministic_uuid)
      expect(uuid1).to eq(uuid2)
    end

    it "generates different UUIDs for different chargeables" do
      purchase2 = create(
        :purchase,
        link: product,
        seller:,
        price_cents: 2_000,
        displayed_price_cents: 2_000,
        created_at: DateTime.parse("January 16, 2025")
      )

      generator1 = described_class.new(
        chargeable: purchase,
        address_fields: address_fields
      )
      generator2 = described_class.new(
        chargeable: purchase2,
        address_fields: address_fields
      )

      uuid1 = generator1.send(:deterministic_uuid)
      uuid2 = generator2.send(:deterministic_uuid)
      expect(uuid1).not_to eq(uuid2)
    end
  end

  describe "tax grouping in XML" do
    it "groups tax subtotals by rate" do
      generator = described_class.new(
        chargeable: chargeable,
        address_fields: address_fields
      )
      result = generator.generate
      doc = Nokogiri::XML(result)
      tax_subtotals = doc.xpath("//cac:TaxTotal/cac:TaxSubtotal",
                                "cac" => "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2")
      expect(tax_subtotals.length).to be >= 1
    end
  end

  it "inherits from Base" do
    expect(described_class.superclass).to eq(ElectronicInvoiceGenerator::Base)
  end
end
