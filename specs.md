# Bashteroids Game
An old school simple vector style game in the tradition of Asteroids.
Played by a single or multiple users, each controlling a simple V shaped space ship that can fire its gun from the front.

## Moving
The ship can be accelerated or slowed down, using its rocket engine. The ships nose can be turned left or right, but without immediately moving the ship into the direction. 
Only once the engine fires the ship is moved into the new direction, still keeping its previous inertia overlayed with the new acceleration. As we are in space there is no friction that slows the ship down. But there needs to be a maximum speed.

The sides of the fixed game window are gates to the opposite side, so a ship can fly through the left side and immediately reappear on the right.

## Objects
Apart from opponents ships there can also appear other objects from the sides.
Before any of these objects appear the side should be glowing for 3 seconds to warn users.

### asteroids
Simple asterois can appear, shaped like rocks, that keep flying a fixed trajectory - also leaving and reentering the screen on its edges.

### UFOs
Small UFOs can appear that can shoot and slowly change their trajectory, but keeping the same velocity they started with.

### Collisions
Collisions of asteroids, UFOs or other ships immediately crash your ship - game over.

### Shots
Ships can fire their gun, in which case a "bullet" appears, fired into the direction the ship is currently facing (not necessarily moving).
It flies with a static trajectory and velocity which is added on top of the current ships movement vector.
Shots do not pass the sides of the game but disappear.
New shots need 2 seconds to load before a new one can be shot.

## Architecture
Bluetooth game controllers should be the primary way to control ships.
The game should run perfectly on iOS with iPads.
Ideally MacOS is also supported with larger screens.
Supporting Android is a nice plus but not required.

## Graphics
Lean towards the classic Asteroids game with a black space background and white items.
Ships use simple colors to distinguish them.

## Sounds
Shooting sounds, accelerating/throttling engine sounds and crash sounds.

## Finish
The game is finished when one ship is left - or none if you play alone against "items"