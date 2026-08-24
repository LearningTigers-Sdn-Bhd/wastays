# frozen_string_literal: true

class Public::ReceiptsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    receipt = Receipt.find_by!(access_token: params[:id])
    presentation = Receipts::Presentation.new(receipt)
    send_data PaymentReceiptPdfService.new(receipt).generate,
      filename: presentation.filename,
      type: "application/pdf",
      disposition: "inline"
  end
end
