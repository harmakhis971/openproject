#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class Relation < ActiveRecord::Base
  scope :of_work_package,
        ->(work_package) { where('from_id = ? OR to_id = ?', work_package, work_package) }

  TYPE_RELATES      = 'relates'.freeze
  TYPE_DUPLICATES   = 'duplicates'.freeze
  TYPE_DUPLICATED   = 'duplicated'.freeze
  TYPE_BLOCKS       = 'blocks'.freeze
  TYPE_BLOCKED      = 'blocked'.freeze
  TYPE_PRECEDES     = 'precedes'.freeze
  TYPE_FOLLOWS      = 'follows'.freeze
  TYPE_INCLUDES     = 'includes'.freeze
  TYPE_PARTOF       = 'partof'.freeze
  TYPE_REQUIRES     = 'requires'.freeze
  TYPE_REQUIRED     = 'required'.freeze

  TYPES = {
    TYPE_RELATES => {
      name: :label_relates_to, sym_name: :label_relates_to, order: 1, sym: TYPE_RELATES
    },
    TYPE_DUPLICATES => {
      name: :label_duplicates, sym_name: :label_duplicated_by, order: 2, sym: TYPE_DUPLICATED
    },
    TYPE_DUPLICATED => {
      name: :label_duplicated_by, sym_name: :label_duplicates, order: 3,
      sym: TYPE_DUPLICATES, reverse: TYPE_DUPLICATES
    },
    TYPE_BLOCKS => {
      name: :label_blocks, sym_name: :label_blocked_by, order: 4, sym: TYPE_BLOCKED
    },
    TYPE_BLOCKED => {
      name: :label_blocked_by, sym_name: :label_blocks, order: 5,
      sym: TYPE_BLOCKS, reverse: TYPE_BLOCKS
    },
    TYPE_PRECEDES => {
      name: :label_precedes, sym_name: :label_follows, order: 6, sym: TYPE_FOLLOWS
    },
    TYPE_FOLLOWS => {
      name: :label_follows, sym_name: :label_precedes, order: 7,
      sym: TYPE_PRECEDES, reverse: TYPE_PRECEDES
    },
    TYPE_INCLUDES => {
      name: :label_includes, sym_name: :label_part_of, order: 8,
      sym: TYPE_PARTOF
    },
    TYPE_PARTOF => {
      name: :label_part_of, sym_name: :label_includes, order: 9,
      sym: TYPE_INCLUDES, reverse: TYPE_INCLUDES
    },
    TYPE_REQUIRES => {
      name: :label_requires, sym_name: :label_required, order: 10,
      sym: TYPE_REQUIRED
    },
    TYPE_REQUIRED => {
      name: :label_required, sym_name: :label_requires, order: 11,
      sym: TYPE_REQUIRES, reverse: TYPE_REQUIRES
    }
  }.freeze

  #validates_inclusion_of :relation_type, in: TYPES.keys + ['hierarchy']
  validates_numericality_of :delay, allow_nil: true

  validate :validate_sanity_of_relation

  before_validation :reverse_if_needed
  before_save :update_schedule

  attr_accessor :relation_type

  def self.relation_column(type)
    if TYPES.key?(type) && TYPES[type][:reverse]
      TYPES[type][:reverse]
    else
      type
    end
  end

  def self.visible(user = User.current)
    where(from_id: WorkPackage.visible(user))
      .where(to_id: WorkPackage.visible(user))
  end

  # TODO: move to typed_dag
  def self.direct
    where("#{_dag_options.type_columns.join(' + ')} = 1")
  end

  def self.of_work_package_or_ancestors(work_package)
    where(to_id: work_package.ancestors_relations.select(:from_id))
      .or(where(to_id: work_package.id))
  end

  def relation_type=(type)
    if type
      column = self.class.relation_column(type)

      send("#{column}=", 1) if column.present?
    end

    @relation_type = type
  end

  # TODO: move parts to typed_dag
  def relation_type
    @relation_type ||= begin
      types = (TYPES.keys & Relation.column_names).select do |name|
        send(name) > 0
      end

      if types.length == 1
        TYPES.detect do |_, type_hash|
          type_hash[:sym] == types[0]
        end[0]
      else
        'mixed'
      end
    end
  end

  def other_work_package(work_package)
    from_id == work_package.id ? descendant : ancestor
  end

  # Returns the relation type for +work_package+
  def relation_type_for(work_package)
    if TYPES[relation_type]
      if from_id == work_package.id
        relation_type
      else
        TYPES[relation_type][:sym]
      end
    end
  end

  def reverse_type
    Relation::TYPES[relation_type] && Relation::TYPES[relation_type][:sym]
  end

  def label_for(work_package)
    TYPES[relation_type] ? TYPES[relation_type][(from_id == work_package.id) ? :name : :sym_name] : :unknown
  end

  def update_schedule
    if TYPE_PRECEDES == relation_type
      self.delay ||= 0
    else
      self.delay = nil
    end
    set_dates_of_target
  end

  def move_target_dates_by(delta)
    to.reschedule_by(delta) if relation_type == TYPE_PRECEDES
  end

  def set_dates_of_target
    soonest_start = successor_soonest_start
    if soonest_start && descendant
      descendant.reschedule_after(soonest_start)
    end
  end

  def successor_soonest_start
    if precedes == 1 && delay && ancestor && (ancestor.start_date || ancestor.due_date)
      (ancestor.due_date || ancestor.start_date) + 1 + delay
    end
  end

  def <=>(relation)
    TYPES[relation_type][:order] <=> TYPES[relation.relation_type][:order]
  end

  # delay is an attribute of Relation but its getter is masked by delayed_job's #delay method
  # here we overwrite dj's delay method with the one reading the attribute
  # since we don't plan to use dj with Relation objects, this should be fine
  def delay
    self[:delay]
  end

  def canonical_type
    if TYPES.key?(relation_type) &&
       TYPES[relation_type][:reverse]
      TYPES[relation_type][:reverse]
    else
      relation_type
    end
  end

  def shared_hierarchy?
    ancestor.descendants.include?(descendant) || descendant.ancestors.include?(ancestor)
  end

  private

  def validate_sanity_of_relation
    return unless ancestor && descendant

    errors.add :to_id, :invalid if from_id == to_id
    errors.add :to_id, :not_same_project unless ancestor.project_id == descendant.project_id ||
                                                Setting.cross_project_work_package_relations?
    errors.add :base, :cant_link_a_work_package_with_a_descendant if shared_hierarchy?
  end

  # Reverses the relation if needed so that it gets stored in the proper way
  def reverse_if_needed
    if TYPES.key?(relation_type) && TYPES[relation_type][:reverse]
      work_package_tmp = descendant
      self.descendant = ancestor
      self.ancestor = work_package_tmp
      self.relation_type = TYPES[relation_type][:reverse]
    end
  end
end
