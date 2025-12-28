class TransactionalMailer < ApplicationMailer
  def auction_win(settlement_id)
    @settlement = AuctionSettlement.includes(:auction, :winning_user).find(settlement_id)
    @auction = @settlement.auction
    @user = @settlement.winning_user
    return if @user.blank? || @auction.blank?

    @wins_url = build_wins_url

    mail(
      to: @user.email_address,
      subject: "You won #{@auction.title} on X-Bid"
    )
  end

  def purchase_receipt(purchase_id)
    @purchase = Purchase.includes(:bid_pack, :user).find(purchase_id)
    @user = @purchase.user
    @bid_pack = @purchase.bid_pack
    return if @user.blank? || @bid_pack.blank?

    mail(
      to: @user.email_address,
      subject: "Your X-Bid purchase receipt"
    )
  end

  private

  def build_wins_url
    ENV.fetch("FRONTEND_WINS_URL", "#{ENV.fetch("FRONTEND_URL", "http://localhost:5173")}/wins")
  end
end
