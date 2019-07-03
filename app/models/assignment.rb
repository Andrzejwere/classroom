# frozen_string_literal: true

class Assignment < ApplicationRecord
  include Flippable
  include GitHubPlan
  include ValidatesNotReservedWord
  include StafftoolsSearchable

  define_pg_search(columns: %i[id title slug])

  default_scope { where(deleted_at: nil) }

  has_one :assignment_invitation, dependent: :destroy, autosave: true
  has_one :deadline, dependent: :destroy, as: :assignment

  has_many :assignment_repos, dependent: :destroy
  has_many :users,            through:   :assignment_repos

  belongs_to :creator, class_name: "User"
  belongs_to :organization

  validates :creator, presence: true

  validates :organization, presence: true

  validates :title, presence: true
  validates :title, length: { maximum: 60 }
  validates :title, uniqueness: { scope: :organization_id }
  validates_not_reserved_word :title

  validates :slug, uniqueness: { scope: :organization_id }
  validates :slug, presence: true
  validates :slug, length: { maximum: 60 }
  validates :slug, format: { with: /\A[-a-zA-Z0-9_]*\z/,
                             message: "should only contain letters, numbers, dashes and underscores" }

  validates :assignment_invitation, presence: true

  validate :uniqueness_of_slug_across_organization
  validate :starter_code_repository_not_empty

  validate :starter_code_repository_is_a_template_repository

  alias_attribute :invitation, :assignment_invitation
  alias_attribute :repos, :assignment_repos

  def private?
    !public_repo
  end

  def public?
    public_repo
  end

  def starter_code?
    starter_code_repo_id.present?
  end

  def template_repos_enabled?
    template_repos_enabled
  end

  def template_repos_disabled?
    !template_repos_enabled?
  end

  def use_template_repos?
    starter_code? && template_repos_enabled
  end

  def use_importer?
    starter_code? && template_repos_disabled?
  end

  def starter_code_repository
    return unless starter_code?
    @starter_code_repository ||= GitHubRepository.new(creator.github_client, starter_code_repo_id)
  end

  def to_param
    slug
  end

  private

  def uniqueness_of_slug_across_organization
    return if GroupAssignment.where(slug: slug, organization: organization).blank?
    errors.add(:slug, :taken)
  end

  def starter_code_repository_not_empty
    return unless starter_code? && starter_code_repository.empty?
    errors.add :starter_code_repository, "cannot be empty. Select a repository that is not empty or create the"\
      " assignment without starter code."
  end

  def starter_code_repository_is_a_template_repository
    return unless starter_code? && use_template_repos?

    options = { accept: "application/vnd.github.baptiste-preview" }
    endpoint_url = "https://api.github.com/repositories/#{starter_code_repo_id}"
    starter_code_github_repository = creator.github_client.get(endpoint_url, options)

    errors.add(
      :starter_code_repository,
      "is not a template repository. Make it a template repository to use template repository cloning."
    ) unless starter_code_github_repository.is_template
  end
end
