import 'package:flutter/material.dart';

/// How a menu item looks on the Sell screen: an emoji and a colour by its
/// heading, so a cashier finds "Chapati" by sight during the rush, not by
/// reading every tile.

/// Matched in order against the item's name (lower case); first match wins.
const _emojis = <(String, String)>[
  ('silver', '🥡'),
  ('beef', '🥩'),
  ('fish', '🐟'),
  ('chicken', '🍗'),
  ('goat', '🍖'),
  ('mulokoni', '🍲'),
  ('peas', '🫛'),
  ('bean', '🫘'),
  ('g.nut', '🥜'),
  ('katogo', '🍲'),
  ('pilau', '🍚'),
  ('rice', '🍚'),
  ('plate', '🍛'),
  ('milk tea', '🍵'),
  ('black tea', '☕'),
  ('tea', '🍵'),
  ('coffee', '☕'),
  ('mandazi', '🍩'),
  ('chapati', '🫓'),
  ('rolex', '🌯'),
  ('gonja', '🍌'),
  ('banana', '🍌'),
  ('samosa', '🥟'),
  ('bun', '🍞'),
  ('bread', '🍞'),
  ('cake', '🍰'),
  ('sweet potato', '🍠'),
  ('yam', '🍠'),
  ('cassava', '🥔'),
  ('omelette', '🍳'),
  ('egg', '🥚'),
  ('sausage', '🌭'),
  ('pancake', '🥞'),
  ('passion', '🧃'),
  ('juice', '🧃'),
  ('minute maid', '🧃'),
  ('mocktail', '🍹'),
  ('bushera', '🥣'),
  ('eshande', '🥛'),
  ('water', '💧'),
  ('soda', '🥤'),
  ('glass', '🥛'),
];

const _headingEmojis = {
  'lunch': '🍛',
  'breakfast': '🍳',
  'drinks': '🥤',
  'snacks': '🥨',
};

String emojiFor(String name, String category) {
  final n = name.toLowerCase();
  for (final (key, emoji) in _emojis) {
    if (n.contains(key)) return emoji;
  }
  return _headingEmojis[category.toLowerCase()] ?? '🍽️';
}

String headingEmoji(String heading) =>
    _headingEmojis[heading.toLowerCase()] ?? '🍽️';

/// A tile's colours: a soft gradient and a strong accent for its badge.
class TileLook {
  const TileLook(this.top, this.bottom, this.accent);

  final Color top;
  final Color bottom;
  final Color accent;
}

/// A few shades per heading, so neighbouring tiles differ a little while a
/// heading keeps one family of colour: warm for lunch, sunny for
/// breakfast, cool for drinks.
const _looks = <String, List<TileLook>>{
  'lunch': [
    TileLook(Color(0xFFFFE7D6), Color(0xFFFFCBA8), Color(0xFFD9622B)),
    TileLook(Color(0xFFFFE0E0), Color(0xFFFFB9B0), Color(0xFFC9423A)),
    TileLook(Color(0xFFFFEBD0), Color(0xFFFFD08A), Color(0xFFCB7A00)),
    TileLook(Color(0xFFF7E3D9), Color(0xFFEFC0A6), Color(0xFFA4502C)),
  ],
  'breakfast': [
    TileLook(Color(0xFFFFF6D1), Color(0xFFFFE38A), Color(0xFFB98500)),
    TileLook(Color(0xFFFFF0DA), Color(0xFFFFD6A0), Color(0xFFC0711A)),
    TileLook(Color(0xFFF3F8D6), Color(0xFFDDEB9C), Color(0xFF6E8B12)),
    TileLook(Color(0xFFFFEFE6), Color(0xFFFFCDB6), Color(0xFFC25B34)),
  ],
  'drinks': [
    TileLook(Color(0xFFDDF4F8), Color(0xFFA9E1EC), Color(0xFF1C8AA0)),
    TileLook(Color(0xFFE3EEFF), Color(0xFFB7CEFF), Color(0xFF3563C9)),
    TileLook(Color(0xFFE6F8EC), Color(0xFFB4E8C4), Color(0xFF2A9152)),
    TileLook(Color(0xFFF1E6FF), Color(0xFFD5BDFF), Color(0xFF7446C2)),
  ],
};

const _otherLooks = [
  TileLook(Color(0xFFF1E6FF), Color(0xFFD9C4FF), Color(0xFF7446C2)),
  TileLook(Color(0xFFFFE6F1), Color(0xFFFFC2DC), Color(0xFFB83B78)),
];

TileLook lookFor(String name, String category) {
  final family = _looks[category.toLowerCase()] ?? _otherLooks;
  final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff);
  return family[hash % family.length];
}
