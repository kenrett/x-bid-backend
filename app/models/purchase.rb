class Purchase < ApplicationRecord
  belongs_to :user
  belongs_to :bid_pack
end
