// Copyright 2026 Aelo contributors. BSD-style license.
#ifndef AELO_WORKSPACE_TREE_H_
#define AELO_WORKSPACE_TREE_H_

#include <algorithm>
#include <cstddef>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace aelo {
// Engine-independent, ordered forest. Only Spaces are roots; only Spaces and
// folders can contain children. A page's id is unrelated to its URL or engine
// tab index. Persistence adapters must validate a whole snapshot before use.
enum class Kind { kSpace, kFolder, kPage };
struct Node {
  std::string id;
  std::string parent;
  std::string title;
  Kind kind = Kind::kFolder;
  std::string url;
  bool pinned = false;
  bool expanded = true;
  bool custom_title = false;
};
class WorkspaceTree {
public:
  WorkspaceTree();
  ~WorkspaceTree();
  WorkspaceTree(const WorkspaceTree &);
  WorkspaceTree &operator=(const WorkspaceTree &);
  const std::vector<Node> &nodes() const { return nodes_; }
  const Node *Find(const std::string &id) const {
    for (const auto &n : nodes_)
      if (n.id == id)
        return &n;
    return nullptr;
  }
  Node *Find(const std::string &id) {
    return const_cast<Node *>(std::as_const(*this).Find(id));
  }
  std::vector<std::string> Children(const std::string &parent) const {
    std::vector<std::string> ids;
    for (const auto &n : nodes_)
      if (n.parent == parent)
        ids.push_back(n.id);
    return ids;
  }
  std::string SpaceOf(std::string id) const {
    // Bounded even when validating an untrusted cycle.
    for (size_t i = 0; i <= nodes_.size(); ++i) {
      const auto *n = Find(id);
      if (!n)
        return {};
      if (n->kind == Kind::kSpace)
        return n->id;
      id = n->parent;
    }
    return {};
  }
  bool CanMove(const std::string &id, const std::string &parent) const {
    const auto *n = Find(id);
    const auto *p = Find(parent);
    if (!n || (n->kind == Kind::kSpace ? !parent.empty()
                                       : (!p || p->kind == Kind::kPage)))
      return false;
    std::string ancestor = parent;
    for (size_t i = 0; !ancestor.empty() && i <= nodes_.size(); ++i) {
      if (ancestor == id)
        return false;
      const auto *current = Find(ancestor);
      if (!current)
        return false;
      ancestor = current->parent;
    }
    return ancestor.empty();
  }
  bool Validate() const {
    // Bound recursive UI work and validate in O(nodes * maximum_depth), even
    // for malformed snapshots with long chains or cycles.
    std::unordered_map<std::string, const Node *> index;
    for (const auto &n : nodes_) {
      if (n.id.empty() || n.title.empty() || !index.emplace(n.id, &n).second ||
          (n.kind != Kind::kSpace && n.kind != Kind::kFolder &&
           n.kind != Kind::kPage) ||
          (n.kind == Kind::kSpace && !n.parent.empty()) ||
          (n.kind != Kind::kSpace && n.parent.empty()) ||
          (n.kind != Kind::kPage && (!n.url.empty() || n.pinned)))
        return false;
    }
    for (const auto &n : nodes_) {
      const Node *ancestor = &n;
      size_t depth = 0;
      while (ancestor->kind != Kind::kSpace) {
        if (++depth > 128)
          return false;
        auto found = index.find(ancestor->parent);
        if (found == index.end() || found->second->kind == Kind::kPage)
          return false;
        ancestor = found->second;
      }
    }
    return true;
  }
  // Rejected snapshots and edits leave the previous valid model untouched.
  bool Load(std::vector<Node> nodes) {
    WorkspaceTree candidate;
    candidate.nodes_ = std::move(nodes);
    if (!candidate.Validate())
      return false;
    nodes_ = std::move(candidate.nodes_);
    return true;
  }
  bool Add(Node node) {
    if (node.id.empty() || Find(node.id))
      return false;
    auto next = nodes_;
    next.push_back(std::move(node));
    return Load(std::move(next));
  }
  bool Rename(const std::string &id, const std::string &title) {
    auto *n = Find(id);
    if (!n || title.empty())
      return false;
    n->title = title;
    n->custom_title = true;
    return true;
  }
  // Position is in the destination's child list AFTER removal of this node.
  bool Move(const std::string &id, const std::string &parent, size_t position) {
    if (!CanMove(id, parent))
      return false;
    auto next = nodes_;
    auto it = std::find_if(next.begin(), next.end(),
                           [&](const Node &n) { return n.id == id; });
    Node moved = *it;
    next.erase(it);
    moved.parent = parent;
    auto insertion = next.end();
    size_t seen = 0;
    for (auto i = next.begin(); i != next.end(); ++i) {
      if (i->parent == parent && seen++ == position) {
        insertion = i;
        break;
      }
    }
    next.insert(insertion, std::move(moved));
    return Load(std::move(next));
  }
  // Never implicitly delete a subtree or any page.
  bool RemoveEmpty(const std::string &id) {
    if (!Find(id) || !Children(id).empty())
      return false;
    std::erase_if(nodes_, [&](const Node &n) { return n.id == id; });
    return true;
  }

private:
  std::vector<Node> nodes_;
};
} // namespace aelo
#endif
