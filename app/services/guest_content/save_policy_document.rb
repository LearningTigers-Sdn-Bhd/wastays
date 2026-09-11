# frozen_string_literal: true

module GuestContent
  # Writes one fixed card on the Policies page.
  #
  # Each card owns a single knowledge document, found by its policy key. The
  # card has no title field, so the title comes from the card itself and the
  # hotel writes the text only.
  #
  # A card with no text keeps no row. Clearing the text removes the document,
  # which stops an empty policy from reaching the AI Concierge.
  class SavePolicyDocument
    def self.call(...) = new(...).call

    def initialize(hotel, policy_key, title, content)
      @hotel = hotel
      @policy_key = policy_key.to_s
      @title = title
      @content = content.to_s
    end

    def call
      return destroy_document if @content.strip.blank?

      document.assign_attributes(
        title: title,
        category: "policy",
        source_type: "text",
        content: @content,
        metadata: (document.metadata || {}).merge("policy_key" => policy_key)
      )
      document.save
    end

    def document
      @document ||= existing_document || hotel.knowledge_documents.build(
        category: "policy",
        source_type: "text",
        title: title,
        metadata: { "policy_key" => policy_key }
      )
    end

    private

    attr_reader :hotel, :policy_key, :title

    def existing_document
      hotel.knowledge_documents.where(category: "policy").with_policy_key(policy_key).first
    end

    def destroy_document
      existing_document&.destroy
      @document = hotel.knowledge_documents.build(
        category: "policy",
        source_type: "text",
        title: title,
        metadata: { "policy_key" => policy_key }
      )
      true
    end
  end
end
