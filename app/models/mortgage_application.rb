class MortgageApplication < ApplicationRecord
  belongs_to :user
  has_one :assessment, dependent: :destroy

  validates :annual_income_cents, presence: true, numericality: { greater_than: 0 }
  validates :monthly_expenses_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :deposit_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :property_value_cents, presence: true, numericality: { greater_than: 0 }
  validates :term_years, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :assessed, -> { joins(:assessment).where(assessments: { status: :completed }) }
  scope :unassessed, -> { where.missing(:assessment) }
end
