class SampleControlledVocab < ApplicationRecord
  # attr_accessible :title, :description, :sample_controlled_vocab_terms_attributes

  has_many :sample_controlled_vocab_terms, inverse_of: :sample_controlled_vocab,
                                           after_add: :update_sample_type_templates,
                                           after_remove: :update_sample_type_templates,
                                           dependent: :destroy
  has_many :sample_attributes, inverse_of: :sample_controlled_vocab
  has_many :custom_metadata_attributes, inverse_of: :sample_controlled_vocab

  has_many :sample_types, through: :sample_attributes
  has_many :samples, through: :sample_types
  belongs_to :repository_standard, inverse_of: :sample_controlled_vocabs

  validates :title, presence: true, uniqueness: true
  validates :source_ontology, inclusion: { in: Ebi::OlsClient.ontology_keys, allow_nil: true }
  validates :ols_root_term_uri, url: { allow_nil: true }

  accepts_nested_attributes_for :sample_controlled_vocab_terms, allow_destroy: true
  accepts_nested_attributes_for :repository_standard, :reject_if => :check_repository_standard

  before_create :fetch_ontology_terms

  grouped_pagination

  def labels
    sample_controlled_vocab_terms.collect(&:label)
  end

  def includes_term?(value)
    labels.include?(value)
  end

  def can_delete?(user = User.current_user)
    sample_types.empty? && can_edit?(user)
  end

  def can_edit?(user = User.current_user)
    samples.empty? && user && (!Seek::Config.project_admin_sample_type_restriction || user.is_admin_or_project_administrator?) && Seek::Config.samples_enabled
  end

  def self.can_create?
    # criteria is the same, and likely to always be
    SampleType.can_create?
  end

  private

  def update_sample_type_templates(_term)
    sample_types.each(&:queue_template_generation) unless new_record?
  end

  def check_repository_standard(repo)
    if _repository_standard = RepositoryStandard.where(title: repo["title"], group_tag: repo["group_tag"]).first
      self.repository_standard = _repository_standard
      return true
    end
    return false
  end

  def fetch_ontology_terms
    if source_ontology.present? && ols_root_term_uri.present?
      client = Ebi::OlsClient.new
      terms = client.all_descendants(source_ontology, ols_root_term_uri)
      hash = {}
      terms.each_with_index do |term, i|
        hash[(i + 1).to_s] = term
      end

      self.sample_controlled_vocab_terms_attributes = hash
    end
  end
end
