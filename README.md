# The Xenon Engine

## Introduction

The Xenon engine is focused for 2D games. It provides a feature-rich and easy to use interface for developing games.

## Documentation

**There is an LDoc generated documentation website available in the `docs` folder. It will provide you with better information.**

### log (string)

A logging function.

### setScene (string)

Sets the current scene.

### getScene ()

Gets the current scene name.

### clearSceneSprites (string)

Clears the sprites in a scene.

### clearScreen ()

Clear the screen and dirty rects.

### titleScreen ()

Show the xenon title screen.

### setCWD (string)

Set CWD for xenon to reference.

### sprite:SetPosition (x, y)

Set the direct position of a sprite.

### sprite:GetSize ()

Returns the size of the sprite.

### sprite:Move (dx, dy)

Moves the sprite by a delta amount.

### sprite:Delete (time)

Delete a sprite after a certain amount of time.

### sprite:SetScene (scene)

Sets the sprite's scene.

### sprite:SetLayer (layer)

Sets the sprite's layer.

### sprite:GetMetadataValue (key)

Gets a metadata value from the sprite.  Useful for tracking health or other stats.

### sprite:SetMetadataValue (key, value)

Sets a metadata value to the sprite.  Useful for tracking health or other stats.

### sprite:AttachOnSpriteClick (event, func)

Attach a callback function to an event.

### sprite:SmoothPosition (x, y, time)

Linearly move a sprite to a direct position.

### sprite:SmoothMove (x, y, time)

Linearly move a sprite by a delta amount.

### sprite:SetIdle (isIdle)

Set a sprite's idle value.

### sprite:FireAnimation (animation)

Fire a sprite's animation.

### newSpriteRef (string, string)

Creates a new animated sprite from a reference file.

### newStillSpriteRef (string, string)

Creates a new static sprite from a reference file.

### inputLoop ()

Starts the input event processing loop.

### registerKey (string, function)

Registers a callback for key events.

### getKeyState (string)

Gets the current state of a key.

### clearKeyTransients ()

Clears transient key states (press/release).

### createMovementSystem (table[, table], options)

Creates a movement system for a sprite.

### createProjectileSystem (source, options)

Creates a projectile system for a sprite

### createCollisionGroup ()

Creates a collision group for sprite collision detection.

### update (number)

Updates the game state and renders sprites.

### runGame (function)

Runs the main game loop with the provided update function.

## Explanation

Let's go over this small game.

```lua
local xenon = require("/xenon_engine/main")

local player = xenon.newSpriteRef("player", "testgame/assets/spriterefs/example.spr")
player:SetPosition(10, 10)
player:SetIdle(true)

local movementSystem = xenon.createMovementSystem(player, {
    speed = 5,
    moveInterval = 0.10
})

local projectileSystem = xenon.createProjectileSystem(player, {
    spritePath = "testgame/assets/spriterefs/fire.spr",
    speed = 8,
    lifetime = 3,
    layer = 1
})

xenon.registerKey("e", function(state)
    if state == "press" then
        player:FireAnimation("extraAnim1")
        projectileSystem:Fire(player.facing)
    end
end)

local function gameLoop()
    while true do
        movementSystem:Update()
        
        projectileSystem:Update()
        
        xenon.update(0.05)
        sleep(0.05)
    end
end

xenon.runGame(gameLoop)
```

`example.spr`
```lua
{
    allAnim = {
        duration = 0.3, 
        anims = {"../sprites/example/allAnim1.nfp", "../sprites/example/allAnim2.nfp"}
    },
    allIdle = {
        duration = 1, 
        anims = {"../sprites/example/allIdle.nfp"}
    },
    extraAnim1 = {
        allDirections = true,
        duration = 0.5,
        anims = {"../sprites/example/extraAnim1.nfp"},
        loop = false
    }
}
```
As a small note: Individual `forward`, `left`, etc. and idle animations can be provided if you would prefer a different animation for each direction. This tutorial uses the `allAnim` and `allIdle` feature to make this breifer.

`fire.spr` (stillSprite)
```lua
{
    sprite = "../sprites/fire/fire.nfp"
}
```

To use the xenon engine, you must do as the game does: `local xenon = require("/xenon_engine/main")`.

```lua
local player = xenon.newSpriteRef("player", "testgame/assets/spriterefs/example.spr")
```
Creates a new sprite "player" which uses the sprite reference `example.spr`

```lua
player:SetPosition(10, 10)
player:SetIdle(true)
```
Sets the position and idle of the sprite. See the documentation for more information.

```lua
local movementSystem = xenon.createMovementSystem(player, {
    speed = 5,
    moveInterval = 0.10
})
```
Instead of writing a long chain of `registerKey`s for getting input, a simple `createMovementSystem` function exists that automatically allows W, A, S and D to move the sprite.

```lua
local projectileSystem = xenon.createProjectileSystem(player, {
    spritePath = "testgame/assets/spriterefs/fire.spr",
    speed = 8,
    lifetime = 3,
    layer = 1
})
```
This creates a reusable projectile system, so that `projectileSystem:Fire` call be called and used easily many times.

```lua
xenon.registerKey("e", function(state)
    if state == "press" then
        player:FireAnimation("extraAnim1")
        projectileSystem:Fire(player.facing)
    end
end)
```
This registers the "e" key to fire the extra animation and fire the projectile.

```lua
local function gameLoop()
    while true do
        movementSystem:Update()
        projectileSystem:Update()
        
        xenon.update(0.05)
        sleep(0.05)
    end
end

xenon.runGame(gameLoop)
```
This last part is the game and render loop. It is almost entirely handled internally, so it is very compact.
