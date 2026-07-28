# frozen_string_literal: true

class Public::ReceiptsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    receipt = Receipt.find_by!(access_token: params[:id])
    send_data PaymentReceiptPdfService.new(receipt).generate,
      filename: "payment-receipt-#{receipt.public_number}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end
end
