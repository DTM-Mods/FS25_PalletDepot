"""Approved depot-pallet dimensions shared by Blender, XML generation and checks."""
WIDTH = 1.2
DEPTH = 0.8
DECK = 0.144
LAYER_HEIGHT = 0.22
MIN_COLLISION_SCALE = 0.001
LAYERS = {1000: 1, 2500: 3, 5000: 6}


def height(size):
    return DECK + LAYERS[size] * LAYER_HEIGHT
