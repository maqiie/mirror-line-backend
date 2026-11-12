# One equity reading per account every ~5 minutes; feeds the dashboard's equity chart.
class EquitySample < ApplicationRecord
  belongs_to :trading_account
  validates :at, :equity, presence: true
end
