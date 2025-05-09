// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../common.dart';
import '../js_backend/namer.dart' show ModularNamer;
import 'codegen.dart' show CodegenPhase;
import 'nodes.dart';

/// The [LiveRange] class covers a range where an instruction is live.
class LiveRange {
  final int start;
  // [end] is not final because it can be updated due to loops.
  int end;
  LiveRange(this.start, this.end) {
    assert(start <= end);
  }

  @override
  String toString() => '[$start $end[';
}

/// The [LiveInterval] class contains the list of ranges where an
/// instruction is live.
class LiveInterval {
  /// The id where the instruction is defined.
  int start;
  final List<LiveRange> ranges;
  LiveInterval() : start = -1, ranges = [];

  // We want [HCheck] instructions to have the same name as the
  // instruction it checks, so both instructions should share the same
  // live ranges.
  LiveInterval.forCheck(this.start, LiveInterval checkedInterval)
    : ranges = checkedInterval.ranges;

  /// Update all ranges that are contained in [from, to[ to
  /// die at [to].
  void loopUpdate(int from, int to) {
    for (LiveRange range in ranges) {
      if (from <= range.start && range.end < to) {
        range.end = to;
      }
    }
  }

  /// Add a new range to this interval.
  void add(LiveRange interval) {
    ranges.add(interval);
  }

  /// Returns true if one of the ranges of this interval dies at [at].
  bool diesAt(int at) {
    for (LiveRange range in ranges) {
      if (range.end == at) return true;
    }
    return false;
  }

  @override
  String toString() {
    List<String> res = [];
    for (final interval in ranges) {
      res.add(interval.toString());
    }
    return '(${res.join(", ")})';
  }
}

/// The [LiveEnvironment] class contains the liveIn set of a basic
/// block. A liveIn set of a block contains the instructions that are
/// live when entering that block.
class LiveEnvironment {
  /// The instruction id where the basic block starts. See
  /// [SsaLiveIntervalBuilder.instructionId].
  int startId = -1;

  /// The instruction id where the basic block ends.
  final int endId;

  /// Loop markers that will be updated once the loop header is
  /// visited. The liveIn set of the loop header will be merged into this
  /// environment. [loopMarkers] is a mapping from block header to the
  /// end instruction id of the loop exit block.
  final Map<HBasicBlock, int> loopMarkers = {};

  /// The instructions that are live in this basic block. The values of
  /// the map contain the instruction ids where the instructions die.
  /// It will be used when adding a range to the live interval of an
  /// instruction.
  final Map<HInstruction, int> liveInstructions = {};

  /// Map containing the live intervals of instructions.
  final Map<HInstruction, LiveInterval> liveIntervals;

  LiveEnvironment(this.liveIntervals, this.endId);

  /// Remove an instruction from the liveIn set. This method also
  /// updates the live interval of [instruction] to contain the new
  /// range: [id, / id contained in [liveInstructions] /].
  void remove(HInstruction instruction, int id) {
    LiveInterval interval = liveIntervals.putIfAbsent(
      instruction,
      () => LiveInterval(),
    );
    int? lastId = liveInstructions[instruction];
    // If [lastId] is null, then this instruction is not being used.
    interval.add(LiveRange(id, lastId ?? id));
    // The instruction is defined at [id].
    interval.start = id;
    liveInstructions.remove(instruction);
  }

  /// Add [instruction] to the liveIn set. If the instruction is not
  /// already in the set, we save the id where it dies.
  void add(HInstruction instruction, int userId) {
    // Note that we are visiting the graph in post-dominator order, so
    // the first time we see a variable is when it dies.
    liveInstructions.putIfAbsent(instruction, () => userId);
  }

  /// Merge this environment with [other]. Update the end id of
  /// instructions in case they are different between this and [other].
  void mergeWith(LiveEnvironment other) {
    other.liveInstructions.forEach((HInstruction instruction, int existingId) {
      // If both environments have the same instruction id of where
      // [instruction] dies, there is no need to update the live
      // interval of [instruction]. For example the if block and the
      // else block have the same end id for an instruction that is
      // being used in the join block and defined before the if/else.
      if (existingId == endId) return;
      LiveInterval range = liveIntervals.putIfAbsent(
        instruction,
        () => LiveInterval(),
      );
      range.add(LiveRange(other.startId, existingId));
      liveInstructions[instruction] = endId;
    });
    other.loopMarkers.forEach((k, v) {
      loopMarkers[k] = v;
    });
  }

  void addLoopMarker(HBasicBlock header, int id) {
    assert(!loopMarkers.containsKey(header));
    loopMarkers[header] = id;
  }

  void removeLoopMarker(HBasicBlock header) {
    assert(loopMarkers.containsKey(header));
    loopMarkers.remove(header);
  }

  bool get isEmpty => liveInstructions.isEmpty && loopMarkers.isEmpty;
  bool contains(HInstruction instruction) =>
      liveInstructions.containsKey(instruction);
  @override
  String toString() => liveInstructions.toString();
}

/// Builds the live intervals of each instruction. The algorithm visits
/// the graph post-dominator tree to find the last uses of an
/// instruction, and computes the liveIns of each basic block.
class SsaLiveIntervalBuilder extends HBaseVisitor<void> with CodegenPhase {
  @override
  String get name => 'SsaLiveIntervalBuilder';

  final Set<HInstruction> generateAtUseSite;
  final Set<HIf> controlFlowOperators;

  /// A counter to assign start and end ids to live ranges. The initial
  /// value is not relevant. Note that instructionId goes downward to ease
  /// reasoning about live ranges (the first instruction of a graph has
  /// the lowest id).
  int instructionId = 0;

  /// The liveIns of basic blocks.
  final Map<HBasicBlock, LiveEnvironment> liveInstructions = {};

  /// The live intervals of instructions.
  final Map<HInstruction, LiveInterval> liveIntervals = {};

  /// Controlling conditions for control-flow operators. Control-flow operators,
  /// e.g. `c ? a : b`, have a condition input `c` from the HIf node
  /// at the top of the control flow diamond as well as the HPhi inputs for `a`
  /// and `b` at the bottom of the diamond.
  final Map<HInstruction, HInstruction> _phiToCondition = {};

  SsaLiveIntervalBuilder(this.generateAtUseSite, this.controlFlowOperators) {
    for (HIf ifNode in controlFlowOperators) {
      _phiToCondition[ifNode.joinBlock!.phis.first!] = ifNode.condition;
    }
  }

  @override
  void visitGraph(HGraph graph) {
    visitPostDominatorTree(graph);
    if (!liveInstructions[graph.entry]!.isEmpty) {
      failedAt(currentElementSpannable, 'LiveIntervalBuilder.');
    }
  }

  void markInputsAsLiveInEnvironment(
    HInstruction instruction,
    LiveEnvironment environment,
  ) {
    if (instruction is HPhi) {
      HInstruction? condition = _phiToCondition[instruction];
      if (condition != null) {
        markAsLiveInEnvironment(condition, environment);
      }
    }
    for (int i = 0, len = instruction.inputs.length; i < len; i++) {
      markAsLiveInEnvironment(instruction.inputs[i], environment);
    }
  }

  // Returns the non-HCheck instruction, or the last [HCheck] in the
  // check chain that is not generate at use site.
  //
  // For example:
  //
  //     t1 = GeneratedAtUseSite instruction
  //     t2 = check(t1)
  //     t3 = check(t2)
  //     t4 = use(t3)
  //     t5 = use(t3)
  //     t6 = use(t2)
  //
  // The t1 is generate-at-use site, and the live-range must thus be on t2 and
  // not on the checked instruction t1.
  // When looking for the checkedInstructionOrNonGenerateAtUseSite of t3 we must
  // return t2.
  HInstruction checkedInstructionOrNonGenerateAtUseSite(
    HOutputConstrainedToAnInput check,
  ) {
    HInstruction constraint = check.constrainedInput;
    while (constraint is HOutputConstrainedToAnInput) {
      HInstruction next = constraint.constrainedInput;
      if (generateAtUseSite.contains(next)) break;
      constraint = next;
    }
    return constraint;
  }

  void markAsLiveInEnvironment(
    HInstruction instruction,
    LiveEnvironment environment,
  ) {
    if (generateAtUseSite.contains(instruction)) {
      markInputsAsLiveInEnvironment(instruction, environment);
    } else {
      environment.add(instruction, instructionId);
      // Special case the HCheck instruction to mark the actual
      // checked instruction live. The checked instruction and the
      // [HCheck] will share the same live ranges.
      if (instruction is HOutputConstrainedToAnInput) {
        HInstruction constraint = checkedInstructionOrNonGenerateAtUseSite(
          instruction,
        );
        if (!generateAtUseSite.contains(constraint)) {
          environment.add(constraint, instructionId);
        }
      }
    }
  }

  void removeFromEnvironment(
    HInstruction instruction,
    LiveEnvironment environment,
  ) {
    environment.remove(instruction, instructionId);
    // Special case the HCheck instruction to have the same live
    // interval as the instruction it is checking.
    if (instruction is HOutputConstrainedToAnInput) {
      HInstruction constraint = checkedInstructionOrNonGenerateAtUseSite(
        instruction,
      );
      if (!generateAtUseSite.contains(constraint)) {
        liveIntervals.putIfAbsent(constraint, () => LiveInterval());
        // Unconditionally force the live ranges of the HCheck to
        // be the live ranges of the instruction it is checking.
        liveIntervals[instruction] = LiveInterval.forCheck(
          instructionId,
          liveIntervals[constraint]!,
        );
      }
    }
  }

  @override
  void visitBasicBlock(HBasicBlock node) {
    LiveEnvironment environment = LiveEnvironment(liveIntervals, instructionId);

    // Add to the environment the liveIn of its successor, as well as
    // the inputs of the phis of the successor that flow from this block.
    for (int i = 0; i < node.successors.length; i++) {
      HBasicBlock successor = node.successors[i];
      LiveEnvironment? successorEnv = liveInstructions[successor];
      if (successorEnv != null) {
        environment.mergeWith(successorEnv);
      } else {
        environment.addLoopMarker(successor, instructionId);
      }

      int index = successor.predecessors.indexOf(node);
      for (var phi = successor.phis.first; phi != null; phi = phi.next) {
        markAsLiveInEnvironment(phi.inputs[index], environment);
      }
    }

    // Iterate over all instructions to remove an instruction from the
    // environment and add its inputs.
    HInstruction? instruction = node.last;
    while (instruction != null) {
      if (!generateAtUseSite.contains(instruction)) {
        removeFromEnvironment(instruction, environment);
        markInputsAsLiveInEnvironment(instruction, environment);
      }
      instructionId--;
      instruction = instruction.previous;
    }

    // We just remove the phis from the environment. The inputs of the
    // phis will be put in the environment of the predecessors.
    for (var phi = node.phis.first; phi != null; phi = phi.next) {
      if (!generateAtUseSite.contains(phi)) {
        environment.remove(phi, instructionId);
      }
    }

    // Save the liveInstructions of that block.
    environment.startId = instructionId + 1;
    liveInstructions[node] = environment;

    // If the block is a loop header, we can remove the loop marker,
    // because it will just recompute the loop phis.
    // We also check if this loop header has any back edges. If not,
    // we know there is no loop marker for it.
    if (node.isLoopHeader() && node.predecessors.length > 1) {
      updateLoopMarker(node);
    }
  }

  void updateLoopMarker(HBasicBlock header) {
    LiveEnvironment env = liveInstructions[header]!;
    int lastId = env.loopMarkers[header]!;
    // Update all instructions that are liveIns in [header] to have a
    // range that covers the loop.
    env.liveInstructions.forEach((HInstruction instruction, int id) {
      LiveInterval range = env.liveIntervals.putIfAbsent(
        instruction,
        () => LiveInterval(),
      );
      range.loopUpdate(env.startId, lastId);
      env.liveInstructions[instruction] = lastId;
    });

    env.removeLoopMarker(header);

    // Update all liveIns set to contain the liveIns of [header].
    liveInstructions.forEach((HBasicBlock block, LiveEnvironment other) {
      if (other.loopMarkers.containsKey(header)) {
        env.liveInstructions.forEach((HInstruction instruction, int id) {
          other.liveInstructions[instruction] = id;
        });
        other.removeLoopMarker(header);
        env.loopMarkers.forEach((k, v) {
          other.loopMarkers[k] = v;
        });
      }
    });
  }
}

/// Represents a copy from one instruction to another. The codegen
/// also uses this class to represent a copy from one variable to
/// another.
class Copy<T> {
  final T source;
  final T destination;

  Copy(this.source, this.destination);

  @override
  String toString() => '$destination <- $source';
}

/// A copy handler contains the copies that a basic block needs to do
/// after executing all its instructions.
class CopyHandler {
  /// The copies from an instruction to a phi of the successor.
  final List<Copy<HInstruction>> copies = [];

  /// Assignments from an instruction that does not need a name (e.g. a
  /// constant) to the phi of a successor.
  final List<Copy<HInstruction>> assignments = [];

  void addCopy(HInstruction source, HInstruction destination) {
    copies.add(Copy<HInstruction>(source, destination));
  }

  void addAssignment(HInstruction source, HInstruction destination) {
    assignments.add(Copy<HInstruction>(source, destination));
  }

  @override
  String toString() => 'Copies: $copies, assignments: $assignments';

  bool get isEmpty => copies.isEmpty && assignments.isEmpty;
}

/// Contains the mapping between instructions and their names for code
/// generation, as well as the [CopyHandler] for each basic block.
class VariableNames {
  final Map<HInstruction, String> ownName = {};
  final Map<HBasicBlock, CopyHandler> copyHandlers = {};

  // Used to control heuristic that determines how local variables are declared.
  final Set<String> allUsedNames = {};

  /// Name that is used as a temporary to break cycles in parallel copies. We
  /// make sure this name is not being used anywhere by reserving it when we
  /// allocate names for instructions.
  final String swapTemp = 't0';

  String getSwapTemp() {
    allUsedNames.add(swapTemp);
    return swapTemp;
  }

  int get numberOfVariables => allUsedNames.length;

  String? getName(HInstruction? instruction) {
    return ownName[instruction];
  }

  CopyHandler? getCopyHandler(HBasicBlock block) {
    return copyHandlers[block];
  }

  void addNameUsed(String name) {
    allUsedNames.add(name);
  }

  bool hasName(HInstruction? instruction) => ownName.containsKey(instruction);

  void addCopy(HBasicBlock block, HInstruction source, HPhi destination) {
    CopyHandler handler = copyHandlers.putIfAbsent(block, () => CopyHandler());
    handler.addCopy(source, destination);
  }

  void addAssignment(HBasicBlock block, HInstruction source, HPhi destination) {
    CopyHandler handler = copyHandlers.putIfAbsent(block, () => CopyHandler());
    handler.addAssignment(source, destination);
  }
}

/// Allocates variable names for instructions, making sure they don't collide.
class VariableNamer {
  final VariableNames names;
  final ModularNamer _namer;
  final Set<String> usedNames = {};
  final List<String> freeTemporaryNames = [];
  int temporaryIndex = 0;
  static final RegExp regexp = RegExp('t[0-9]+');

  VariableNamer(LiveEnvironment environment, this.names, this._namer) {
    // [VariableNames.swapTemp] is used when there is a cycle in a copy handler.
    // Therefore we make sure no one uses it.
    usedNames.add(names.swapTemp);

    // All liveIns instructions must have a name at this point, so we
    // add them to the list of used names.
    environment.liveInstructions.forEach((HInstruction instruction, int index) {
      String? name = names.getName(instruction);
      if (name != null) {
        usedNames.add(name);
        names.addNameUsed(name);
      }
    });
  }

  String allocateWithHint(String originalName) {
    int i = 0;
    String name = _namer.safeVariableName(originalName);
    while (usedNames.contains(name)) {
      name = _namer.safeVariableName('$originalName${i++}');
    }
    return name;
  }

  String allocateTemporary() {
    while (freeTemporaryNames.isNotEmpty) {
      String name = freeTemporaryNames.removeLast();
      if (!usedNames.contains(name)) return name;
    }
    String name = 't${temporaryIndex++}';
    while (usedNames.contains(name)) {
      name = 't${temporaryIndex++}';
    }
    return name;
  }

  HPhi? firstPhiUserWithElement(HInstruction instruction) {
    for (HInstruction user in instruction.usedBy) {
      if (user is HPhi && user.sourceElement != null) {
        return user;
      }
    }
    return null;
  }

  String allocateName(HInstruction instruction) {
    String? name;
    if (instruction is HOutputConstrainedToAnInput) {
      // Special case this instruction to use the name of its input if it has
      // one.
      HInstruction temp = instruction;
      do {
        temp = (temp as HOutputConstrainedToAnInput).constrainedInput;
        name = names.ownName[temp];
      } while (name == null && temp is HOutputConstrainedToAnInput);
      if (name != null) return addAllocatedName(instruction, name);
    }

    if (instruction.sourceElement != null) {
      if (instruction.sourceElement!.name != null) {
        name = allocateWithHint(instruction.sourceElement!.name!);
      } else {
        // Source element is synthesized and has no name.
        name = allocateTemporary();
      }
    } else {
      // We could not find an element for the instruction. If the
      // instruction is used by a phi, try to use the name of the phi.
      // Otherwise, just allocate a temporary name.
      HPhi? phi = firstPhiUserWithElement(instruction);
      final phiName = phi?.sourceElement?.name;
      if (phiName != null) {
        name = allocateWithHint(phiName);
      } else {
        name = allocateTemporary();
      }
    }
    return addAllocatedName(instruction, name);
  }

  String addAllocatedName(HInstruction instruction, String name) {
    usedNames.add(name);
    names.addNameUsed(name);
    names.ownName[instruction] = name;
    return name;
  }

  /// Frees [instruction]'s name so it can be used for other instructions.
  void freeName(HInstruction instruction) {
    String? ownName = names.ownName[instruction];
    if (ownName != null) {
      // We check if we have already looked for temporary names
      // because if we haven't, chances are the temporary we allocate
      // in this block can match a phi with the same name in the
      // successor block.
      if (temporaryIndex != 0 && regexp.hasMatch(ownName)) {
        freeTemporaryNames.add(ownName);
      }
      usedNames.remove(ownName);
    }
  }
}

/// Visits all blocks in the graph, sets names to instructions, and
/// creates the [CopyHandler] for each block. This class needs to have
/// the liveIns set as well as all the live intervals of instructions.
/// It visits the graph in dominator order, so that at each entry of a
/// block, the instructions in its liveIns set have names.
///
/// When visiting a block, it goes through all instructions. For each
/// instruction, it frees the names of the inputs that die at that
/// instruction, and allocates a name to the instruction. For each phi,
/// it adds a copy to the CopyHandler of the corresponding predecessor.
class SsaVariableAllocator extends HBaseVisitor<void> implements CodegenPhase {
  @override
  String get name => 'SsaVariableAllocator';

  final ModularNamer _namer;
  final Map<HBasicBlock, LiveEnvironment> liveInstructions;
  final Map<HInstruction, LiveInterval> liveIntervals;
  final Set<HInstruction> generateAtUseSite;

  final VariableNames names;

  SsaVariableAllocator(
    this._namer,
    this.liveInstructions,
    this.liveIntervals,
    this.generateAtUseSite,
  ) : names = VariableNames();

  @override
  void visitGraph(HGraph graph) {
    visitDominatorTree(graph);
  }

  @override
  void visitBasicBlock(HBasicBlock node) {
    VariableNamer variableNamer = VariableNamer(
      liveInstructions[node]!,
      names,
      _namer,
    );

    node.forEachPhi((HPhi phi) {
      handlePhi(phi, variableNamer);
    });

    node.forEachInstruction((HInstruction instruction) {
      handleInstruction(instruction, variableNamer);
    });
  }

  /// Returns whether [instruction] needs a name. Instructions that
  /// have no users or that are generated at use site do not need a name.
  bool needsName(HInstruction instruction) {
    if (instruction is HThis) return false;
    if (instruction is HParameterValue) return true;
    if (instruction.usedBy.isEmpty) return false;
    if (generateAtUseSite.contains(instruction)) return false;
    return !instruction.nonCheck().isCodeMotionInvariant();
  }

  /// Returns whether [instruction] dies at the instruction [at].
  bool diesAt(HInstruction instruction, HInstruction at) {
    LiveInterval atInterval = liveIntervals[at]!;
    LiveInterval instructionInterval = liveIntervals[instruction]!;
    int start = atInterval.start;
    return instructionInterval.diesAt(start);
  }

  void freeUsedNamesAt(
    HInstruction instruction,
    HInstruction at,
    VariableNamer namer,
  ) {
    if (needsName(instruction)) {
      if (diesAt(instruction, at)) {
        namer.freeName(instruction);
      }
    } else if (generateAtUseSite.contains(instruction)) {
      // If the instruction is generated at use site, then all its
      // inputs may also die at [at].
      for (int i = 0, len = instruction.inputs.length; i < len; i++) {
        HInstruction input = instruction.inputs[i];
        freeUsedNamesAt(input, at, namer);
      }
    }
  }

  void handleInstruction(HInstruction instruction, VariableNamer namer) {
    if (generateAtUseSite.contains(instruction)) {
      assert(!liveIntervals.containsKey(instruction));
      return;
    }

    for (int i = 0, len = instruction.inputs.length; i < len; i++) {
      HInstruction input = instruction.inputs[i];
      freeUsedNamesAt(input, instruction, namer);
    }

    if (needsName(instruction)) {
      namer.allocateName(instruction);
    }
  }

  void handlePhi(HPhi phi, VariableNamer namer) {
    if (!needsName(phi)) return;

    for (int i = 0; i < phi.inputs.length; i++) {
      HInstruction input = phi.inputs[i];
      HBasicBlock predecessor = phi.block!.predecessors[i];
      // A [HTypeKnown] instruction never has a name, but its checked
      // input might, therefore we need to do a copy instead of an
      // assignment.
      while (input is HTypeKnown) {
        input = input.inputs[0];
      }
      if (!needsName(input)) {
        names.addAssignment(predecessor, input, phi);
      } else {
        names.addCopy(predecessor, input, phi);
      }
    }

    namer.allocateName(phi);
  }
}
