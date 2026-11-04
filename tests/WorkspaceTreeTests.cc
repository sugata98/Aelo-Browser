#include "../chromium/workspace/aelo_workspace_model.h"
#include <cassert>
#include <iostream>
using aelo::Kind;
using aelo::Node;
using aelo::WorkspaceTree;
int main() {
  WorkspaceTree tree;
  assert(tree.Add({"personal", "", "Personal", Kind::kSpace}));
  assert(tree.Add({"focus", "", "Focus", Kind::kSpace}));
  assert(tree.Add({"projects", "personal", "Projects", Kind::kFolder}));
  assert(tree.Add({"research", "projects", "研究 📚", Kind::kFolder}));
  assert(tree.Add(
      {"page1", "research", "One", Kind::kPage, "https://example.test", true}));
  assert(tree.Add(
      {"page2", "research", "Same URL", Kind::kPage, "https://example.test"}));
  assert(tree.SpaceOf("page1") == "personal");
  const auto original = tree.nodes();
  assert(!tree.Move("projects", "research", 0)); // descendant cycle
  assert(!tree.Move("projects", "projects", 0));
  assert(!tree.Move("projects", "page1", 0)); // page cannot own children
  assert(!tree.Move("personal", "focus", 0)); // nested Space
  assert(!tree.RemoveEmpty("projects"));      // no cascading data loss
  assert(!tree.Add({"page1", "personal", "duplicate", Kind::kPage}));
  assert(!tree.Add({"dangling", "missing", "Bad", Kind::kFolder}));
  assert(tree.nodes().size() == original.size());
  assert(tree.Move("page2", "research", 0));
  assert(tree.Children("research")[0] == "page2");
  assert(
      tree.Move("projects", "focus", 0)); // whole subtree, same engine Profile
  assert(tree.SpaceOf("page1") == "focus");
  assert(tree.Find("page1")->pinned);
  assert(tree.Rename("research", "資料"));
  assert(!tree.Rename("research", ""));
  tree.Find("projects")->expanded = false;
  WorkspaceTree reopened;
  assert(reopened.Load(tree.nodes()));
  assert(reopened.SpaceOf("page1") == "focus");
  assert(!reopened.Find("projects")->expanded);
  assert(reopened.Find("research")->title == "資料");
  auto bad = tree.nodes();
  bad[2].parent = "research";
  assert(!reopened.Load(bad));
  assert(reopened.SpaceOf("page1") == "focus");
  assert(tree.Add({"empty", "personal", "Empty", Kind::kFolder}));
  assert(reopened.Load(tree.nodes()));
  assert(reopened.Find("empty")); // empty folders and Spaces persist
  assert(reopened.RemoveEmpty("empty"));
  assert(reopened.RemoveEmpty("personal"));
  // Exercise a hierarchy well beyond Chromium's one-level groups.
  std::string parent = "focus";
  for (int i = 0; i < 100; ++i) {
    std::string id = "depth" + std::to_string(i);
    assert(reopened.Add({id, parent, id, Kind::kFolder}));
    parent = id;
  }
  assert(reopened.Validate());
  // Oversized depth / invalid enum snapshots fail without replacing valid data.
  auto too_deep = reopened.nodes();
  std::string deep_parent = "depth99";
  for (int i = 100; i < 140; ++i) {
    auto id = "depth" + std::to_string(i);
    too_deep.push_back({id, deep_parent, id, Kind::kFolder});
    deep_parent = id;
  }
  assert(!reopened.Load(too_deep));
  assert(reopened.Find("depth99") && !reopened.Find("depth100"));
  auto invalid_kind = reopened.nodes();
  invalid_kind.front().kind = static_cast<Kind>(99);
  assert(!reopened.Load(invalid_kind));
  assert(!reopened.Move("depth0", "depth99", 0));
  std::cout << "PASS: nested tree, cycles, ordering, moves, pins, empty "
               "containers, snapshot recovery\n";
}
