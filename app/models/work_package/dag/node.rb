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

module WorkPackage::Dag::Node
  extend ActiveSupport::Concern

  included do
    has_one :parent_relation,
            -> {
              where(relations: { relation_type: 'hierarchy',
                                 depth: 1 })
            },
            class_name: 'Relation',
            foreign_key: 'to_id'

    has_one :parent,
            through: :parent_relation,
            source: :from,
            class_name: 'WorkPackage'

    has_many :child_relations,
             -> {
               where(relations: { relation_type: 'hierarchy',
                                  depth: 1 })
             },
             class_name: 'Relation',
             foreign_key: 'from_id'

    has_many :children,
             through: :child_relations,
             source: :to

    has_many :descendant_relations,
             -> { where(relations: { relation_type: 'hierarchy' }) },
             class_name: 'Relation',
             foreign_key: 'from_id'

    has_many :descendants,
             through: :descendant_relations,
             source: :to

    has_many :ancestor_relations,
             -> { where(relations: { relation_type: 'hierarchy' }) },
             class_name: 'Relation',
             foreign_key: 'to_id'

    has_many :ancestors,
             through: :ancestor_relations,
             source: :from

    def leaf?
      !relations_from.where(relation_type: 'hierarchy').exists?
    end

    def child?
      !!parent_relation
    end

    def in_closure?(other_work_package)
      ancestor_relations
        .where(relations: { from_id: other_work_package })
        .or(descendant_relations.where(relations: { to_id: other_work_package }))
        .exists?
    end
  end
end
