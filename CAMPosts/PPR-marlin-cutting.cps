/**
  Copyright (C) 2015-2016 by Autodesk, Inc.
  All rights reserved.

  Jet template post processor configuration. This post is intended to show
  the capabilities for use with waterjet, laser, and plasma cutters. It only
  serves as a template for customization for an actual CNC.

  $Revision: 42473 905303e8374380273c82d214b32b7e80091ba92e $
  $Date: 2019-09-04 00:46:02 $

  FORKID {51C1E5C7-D09E-458F-AC35-4A2CE1E0AE32}
*/

description = "PPR V1.0";
vendor = "2AM Innovations";
vendorUrl = "";
legal = "";
certificationLevel = 2;
minimumRevision = 39000;

longDescription = "";

extension = "gcode";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = undefined; // allow any circular motion

// user-defined properties
properties = {
  writeMachine: true, // write machine
  homeAtStart: true, // G28 home before starting
  g0feed: 0, // G0 feed rate
  showSequenceNumbers: false, // show sequence numbers
  sequenceNumberStart: 10, // first sequence number
  sequenceNumberIncrement: 5, // increment for sequence numbers
  allowHeadSwitches: true, // output code to allow heads to be manually switched for piercing and cutting
  useRetracts: true, // output retracts - otherwise only output part contours for importing in third-party jet application
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  delayStart: 1.0, // cutter start delay
  delayStop: 0.1, // cutter stop delay
  probe: true,
  useZAxis: true,
  pierceHeight: .111
};

// user-defined property definitions
propertyDefinitions = {
  writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
  homeAtStart: {title:"Home at start", description:"Home machine with G28 at start of program", group:0, type:"boolean"},
  g0feed: {title:"G0 Feed", description:"Feed rate for G0 moves, -1 for firmware default", group:1, type:"number"},
  delayStart: {title:"Start delay", description:"Delay after starting cutter (seconds)", group:1, type:"number"},
  delayStop: {title:"Stop delay", description:"Delay after stopping cutter (seconds)", group:1, type:"number"},
  probe: {title: "Probe", description: "Specifies whether to use probing.", type: "boolean", value: false, scope: "post"},
  useZAxis: {title: "Use Z axis", description: "Specifies to enable the output for Z coordinates.", type: "boolean", value: false, scope: "post"},
  pierceHeight: {title: "Pierce Height", description: "Specifies the pierce height.", type: "number", value: 0, scope: "post"},
  showSequenceNumbers: {title:"Use sequence numbers", description:"Use sequence numbers for each block of outputted code.", group:1, type:"boolean"},
  sequenceNumberStart: {title:"Start sequence number", description:"The number at which to start the sequence numbers.", group:1, type:"integer"},
  sequenceNumberIncrement: {title:"Sequence number increment", description:"The amount by which the sequence number is incremented by in each block.", group:1, type:"integer"},
  allowHeadSwitches: {title:"Allow head switches", description:"Enable to output code to allow heads to be manually switched for piercing and cutting.", type:"boolean"},
  useRetracts: {title:"Use retracts", description:"Output retracts, otherwise only output part contours for importing into a third-party jet application.", type:"boolean"},
  separateWordsWithSpace: {title:"Separate words with space", description:"Adds spaces between words if 'yes' is selected.", type:"boolean"}
};

var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var zFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, zFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var feedG0Output = createVariable({prefix:"F"}, feedFormat);

// circular output
var iOutput = createReferenceVariable({prefix:"I"}, xyzFormat);
var jOutput = createReferenceVariable({prefix:"J"}, xyzFormat);

var gMotionModal = gFormat; // modal group 1 // G0-G3, ... Marlin needs it on every line
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

function formatComment(text) {
  return ";(" + String(text).replace(/[()]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}

function onOpen() {
  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  if (hasGlobalParameter("material")) {
    writeComment("MATERIAL = " + getGlobalParameter("material"));
  }

  if (hasGlobalParameter("material-hardness")) {
    writeComment("MATERIAL HARDNESS = " + getGlobalParameter("material-hardness"));
  }

  { // stock - workpiece
    var workpiece = getWorkpiece();
    var delta = Vector.diff(workpiece.upper, workpiece.lower);
    if (delta.isNonZero()) {
      writeComment("THICKNESS = " + xyzFormat.format(workpiece.upper.z - workpiece.lower.z));
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90));

  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(20));
    break;
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
}

function onSection() {

  if (isFirstSection() && properties.homeAtStart) {
    writeln("");
    writeBlock(gFormat.format(53), formatComment("Home in G53 so that G54 offsets keep"))
    writeBlock(gFormat.format(28), "O1", formatComment("Optional home"));

    writeBlock(mFormat.format(444),
      "S" + secFormat.format(properties.delayStart),
      "P" + secFormat.format(properties.delayStop),
      formatComment("cutter delays"));
  } else {
    writeln("");
  }

  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);

  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());

  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);

    switch (tool.type) {
    case TOOL_WATER_JET:
      writeComment("Waterjet cutting.");
      break;
    case TOOL_LASER_CUTTER:
      writeComment("Laser cutting");
      break;
    case TOOL_PLASMA_CUTTER:
      writeComment("Plasma cutting");
      break;
    /*
    case TOOL_MARKER:
      writeComment("Marker");
      break;
    */
    default:
      error(localize("The CNC does not support the required tool."));
      return;
    }
    writeln("");

    writeComment("tool.jetDiameter = " + xyzFormat.format(tool.jetDiameter));
    writeComment("tool.jetDistance = " + xyzFormat.format(tool.jetDistance));
    writeln("");

    switch (currentSection.jetMode) {
    case JET_MODE_THROUGH:
      writeComment("THROUGH CUTTING");
      break;
    case JET_MODE_ETCHING:
      writeComment("ETCH CUTTING");
      break;
    case JET_MODE_VAPORIZE:
      writeComment("VAPORIZE CUTTING");
      break;
    default:
      error(localize("Unsupported cutting mode."));
      return;
    }
    writeComment("QUALITY = " + currentSection.quality);

    if (tool.comment) {
      writeComment(tool.comment);
    }
    writeln("");
  }

  // wcs
  if (insertToolCall) { // force work offset when changing tool
    currentWorkOffset = undefined;
  }
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      var code = workOffset - 6;
      if (code > 3) {
        error(localize("Work offset out of range."));
        return;
      }
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(59) + "." + code);
        currentWorkOffset = workOffset;
      }
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }


  if (properties.useZAxis) {
    addPierceHeight(true);
  } else {
    zOutput.disable();
  }

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  /*
  // set coolant after we have positioned at Z
  if (false) {
    var c = mapCoolantTable.lookup(tool.coolant);
    if (c) {
      writeBlock(mFormat.format(c));
    } else {
      warning(localize("Coolant not supported."));
    }
  }
*/

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var zIsOutput = false;
  if (properties.useZAxis && !properties.probe) {
    var previousFinalPosition = isFirstSection() ? initialPosition : getFramePosition(getPreviousSection().getFinalPosition());
    if (xyzFormat.getResultingValue(previousFinalPosition.z) <= xyzFormat.getResultingValue(initialPosition.z)) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
      zIsOutput = true;
    }
  }

  writeBlock(gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y));
  probeHeight();
  heightProbed = true;

  if (properties.useZAxis && !zIsOutput) {
    writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z), formatComment("clearance height"));
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "S" + secFormat.format(seconds));
}

function onCycle() {
  error("Drilling is not supported by CNC.");
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  error("Radius compensation not supported by Marlin.");
}

var heightProbed = false;
function probeHeight() {
  if (properties.probe) {
    writeBlock(gFormat.format(30), "   " + formatComment("probe"));
    writeBlock(gFormat.format(92), "Z0 P1", formatComment("set Z 0 including probe offset"));
    zOutput.reset();
  }
}

var shapeArea = 0;
var shapePerimeter = 0;
var shapeSide = "inner";
var cuttingSequence = "";

function onParameter(name, value) {
  if ((name == "action") && (value == "pierce")) {
    //writeComment("RUN POINT-PIERCE COMMAND HERE");
  } else if (name == "shapeArea") {
    shapeArea = value;
    writeComment("SHAPE AREA = " + xyzFormat.format(shapeArea));
  } else if (name == "shapePerimeter") {
    shapePerimeter = value;
    writeComment("SHAPE PERIMETER = " + xyzFormat.format(shapePerimeter));
  } else if (name == "shapeSide") {
    shapeSide = value;
    writeComment("SHAPE SIDE = " + value);
  } else if (name == "beginSequence") {
    if (value == "piercing") {
      if (cuttingSequence != "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to piercing head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    } else if (value == "cutting") {
      if (cuttingSequence == "piercing") {
        if (properties.allowHeadSwitches) {
          writeln("");
          writeComment("Switch to cutting head before continuing");
          onCommand(COMMAND_STOP);
          writeln("");
        }
      }
    }
    cuttingSequence = value;
  }
}

var deviceOn = false;

function addPierceHeight(enabled) {
  zFormat.setOffset(enabled ? properties.pierceHeight : 0);
  zOutput = createVariable({prefix:"Z"}, zFormat);
  //writeComment("pierceHeight " + (enabled ? "added" : "removed"));
}

function setDeviceMode(enable) {
  if (enable != deviceOn) {
    deviceOn = enable;
    heightProbed = false;

    if (enable) {
      writeBlock(mFormat.format(3), formatComment("Plasma ON"));
      if (zFormat.isSignificant(properties.pierceHeight)) {
        feedOutput.reset();
        var f = (hasParameter("operation:tool_feedEntry") ? getParameter("operation:tool_feedEntry") : toPreciseUnit(1000, MM));
        addPierceHeight(false);
        writeBlock(gMotionModal.format(1), zOutput.format(getCurrentPosition().z), feedOutput.format(f),
          formatComment("top height, entry feedrate"));
      }
    } else {
      writeBlock(mFormat.format(5), formatComment("Plasma OFF"));
      writeln("");
      addPierceHeight(true);
    }
  }
}

function onPower(power) {
  setDeviceMode(power);
}

function rapidFeedBlock() {
  if (properties.g0feed > 0) {
    return feedG0Output.format(properties.g0feed);
  } else {
    return "";
  }
}

function onRapid(_x, _y, _z) {

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var justProbed = false;
  // if plunge move, activate probe if enabled
  if (!x && !y && z && (_z < getCurrentPosition().z) && !heightProbed && !deviceOn) {
    probeHeight();
    justProbed = true;
  }
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    writeBlock(gMotionModal.format(0), x, y, z, rapidFeedBlock(),
      justProbed ? formatComment("top height + pierce height") : "");
  }
}

function onLinear(_x, _y, _z, feed) {

  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || (z && !powerIsOn)) {
    writeBlock(gMotionModal.format(1), x, y, f);
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
      writeComment("feedOutput.reset - f && isMotion");
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {

  // one of X/Y and I/J are required and likewise

  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();
  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), iOutput.format(cx - start.x, 0), jOutput.format(cy - start.y, 0), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  COMMAND_END:2
};

function onCommand(command) {
  switch (command) {
  case COMMAND_POWER_ON:
    return;
  case COMMAND_POWER_OFF:
    return;
  case COMMAND_COOLANT_ON:
    return;
  case COMMAND_COOLANT_OFF:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  setDeviceMode(false);
  forceAny();
}

function onClose() {
  writeln("");

  onCommand(COMMAND_COOLANT_OFF);

  writeBlock(mFormat.format(18), formatComment("Motors off"));

  onImpliedCommand(COMMAND_END);
}
