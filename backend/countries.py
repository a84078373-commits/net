"""Country dial codes + national mobile patterns for WhatsApp OTP."""
from __future__ import annotations

import re
from typing import Any

# iso, flag emoji, Arabic name, English name, dial, national regex (local digits only)
COUNTRIES: list[dict[str, Any]] = [
    {'iso': 'SA', 'flag': '🇸🇦', 'name_ar': 'السعودية', 'name_en': 'Saudi Arabia', 'dial': '966', 'pattern': r'^5\d{8}$', 'example': '5xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'AE', 'flag': '🇦🇪', 'name_ar': 'الإمارات', 'name_en': 'United Arab Emirates', 'dial': '971', 'pattern': r'^5\d{8}$', 'example': '5xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'EG', 'flag': '🇪🇬', 'name_ar': 'مصر', 'name_en': 'Egypt', 'dial': '20', 'pattern': r'^1\d{9}$', 'example': '1xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'KW', 'flag': '🇰🇼', 'name_ar': 'الكويت', 'name_en': 'Kuwait', 'dial': '965', 'pattern': r'^[569]\d{7}$', 'example': '5xxxxxxx', 'local_prefix': ''},
    {'iso': 'BH', 'flag': '🇧🇭', 'name_ar': 'البحرين', 'name_en': 'Bahrain', 'dial': '973', 'pattern': r'^[36]\d{7}$', 'example': '3xxxxxxx', 'local_prefix': ''},
    {'iso': 'QA', 'flag': '🇶🇦', 'name_ar': 'قطر', 'name_en': 'Qatar', 'dial': '974', 'pattern': r'^[3567]\d{7}$', 'example': '3xxxxxxx', 'local_prefix': ''},
    {'iso': 'OM', 'flag': '🇴🇲', 'name_ar': 'عُمان', 'name_en': 'Oman', 'dial': '968', 'pattern': r'^9\d{7}$', 'example': '9xxxxxxx', 'local_prefix': ''},
    {'iso': 'JO', 'flag': '🇯🇴', 'name_ar': 'الأردن', 'name_en': 'Jordan', 'dial': '962', 'pattern': r'^7\d{8}$', 'example': '7xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'IQ', 'flag': '🇮🇶', 'name_ar': 'العراق', 'name_en': 'Iraq', 'dial': '964', 'pattern': r'^7\d{9}$', 'example': '7xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'YE', 'flag': '🇾🇪', 'name_ar': 'اليمن', 'name_en': 'Yemen', 'dial': '967', 'pattern': r'^7\d{8}$', 'example': '7xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'LB', 'flag': '🇱🇧', 'name_ar': 'لبنان', 'name_en': 'Lebanon', 'dial': '961', 'pattern': r'^[3457]\d{7}$', 'example': '3xxxxxxx', 'local_prefix': '0'},
    {'iso': 'PS', 'flag': '🇵🇸', 'name_ar': 'فلسطين', 'name_en': 'Palestine', 'dial': '970', 'pattern': r'^5\d{8}$', 'example': '5xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'MA', 'flag': '🇲🇦', 'name_ar': 'المغرب', 'name_en': 'Morocco', 'dial': '212', 'pattern': r'^[67]\d{8}$', 'example': '6xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'DZ', 'flag': '🇩🇿', 'name_ar': 'الجزائر', 'name_en': 'Algeria', 'dial': '213', 'pattern': r'^[567]\d{8}$', 'example': '5xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'TN', 'flag': '🇹🇳', 'name_ar': 'تونس', 'name_en': 'Tunisia', 'dial': '216', 'pattern': r'^[2459]\d{7}$', 'example': '2xxxxxxx', 'local_prefix': ''},
    {'iso': 'TR', 'flag': '🇹🇷', 'name_ar': 'تركيا', 'name_en': 'Turkey', 'dial': '90', 'pattern': r'^5\d{9}$', 'example': '5xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'IN', 'flag': '🇮🇳', 'name_ar': 'الهند', 'name_en': 'India', 'dial': '91', 'pattern': r'^[6-9]\d{9}$', 'example': '9xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'PK', 'flag': '🇵🇰', 'name_ar': 'باكستان', 'name_en': 'Pakistan', 'dial': '92', 'pattern': r'^3\d{9}$', 'example': '3xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'BD', 'flag': '🇧🇩', 'name_ar': 'بنغلاديش', 'name_en': 'Bangladesh', 'dial': '880', 'pattern': r'^1\d{9}$', 'example': '1xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'ID', 'flag': '🇮🇩', 'name_ar': 'إندونيسيا', 'name_en': 'Indonesia', 'dial': '62', 'pattern': r'^8\d{8,11}$', 'example': '8xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'MY', 'flag': '🇲🇾', 'name_ar': 'ماليزيا', 'name_en': 'Malaysia', 'dial': '60', 'pattern': r'^1\d{8,9}$', 'example': '1xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'PH', 'flag': '🇵🇭', 'name_ar': 'الفلبين', 'name_en': 'Philippines', 'dial': '63', 'pattern': r'^9\d{9}$', 'example': '9xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'US', 'flag': '🇺🇸', 'name_ar': 'الولايات المتحدة', 'name_en': 'United States', 'dial': '1', 'pattern': r'^[2-9]\d{9}$', 'example': '2015550123', 'local_prefix': ''},
    {'iso': 'GB', 'flag': '🇬🇧', 'name_ar': 'بريطانيا', 'name_en': 'United Kingdom', 'dial': '44', 'pattern': r'^7\d{9}$', 'example': '7xxxxxxxxx', 'local_prefix': '0'},
    {'iso': 'DE', 'flag': '🇩🇪', 'name_ar': 'ألمانيا', 'name_en': 'Germany', 'dial': '49', 'pattern': r'^1\d{9,11}$', 'example': '15xxxxxxxx', 'local_prefix': '0'},
    {'iso': 'FR', 'flag': '🇫🇷', 'name_ar': 'فرنسا', 'name_en': 'France', 'dial': '33', 'pattern': r'^[67]\d{8}$', 'example': '6xxxxxxxx', 'local_prefix': '0'},
]

_BY_ISO = {c['iso']: c for c in COUNTRIES}


def get_country(iso: str | None) -> dict[str, Any] | None:
    if not iso:
        return _BY_ISO['SA']
    return _BY_ISO.get(str(iso).upper().strip())


def countries_public(lang: str = 'ar') -> list[dict[str, Any]]:
    out = []
    for c in COUNTRIES:
        out.append(
            {
                'iso': c['iso'],
                'flag': c['flag'],
                'name': c['name_ar'] if lang != 'en' else c['name_en'],
                'dial': c['dial'],
                'example': c['example'],
                'local_prefix': c.get('local_prefix') or '',
            }
        )
    return out


def _digits(value: str) -> str:
    return re.sub(r'\D+', '', value or '')


def normalize_national(country: dict[str, Any], raw: str) -> str:
    """Strip spaces/+ and leading trunk 0 → national mobile digits."""
    digits = _digits(raw)
    dial = country['dial']
    # Pasted full international number
    if digits.startswith(dial) and len(digits) > len(dial) + 5:
        digits = digits[len(dial) :]
    # Pasted with leading 0
    prefix = country.get('local_prefix') or ''
    if prefix and digits.startswith(prefix) and not re.match(country['pattern'], digits):
        candidate = digits[len(prefix) :]
        if re.match(country['pattern'], candidate):
            digits = candidate
    return digits


def validate_and_store_phone(country_iso: str | None, national_raw: str) -> tuple[str, str, str]:
    """Return (storage_phone, e164_digits, iso).

    Saudi stays 05xxxxxxxx for backward compatibility with existing accounts.
    Other countries store E.164 without plus (e.g. 9715xxxxxxx).
    """
    country = get_country(country_iso) or _BY_ISO['SA']
    national = normalize_national(country, national_raw)
    if not re.match(country['pattern'], national):
        raise ValueError('invalid_national')
    e164 = country['dial'] + national
    if country['iso'] == 'SA':
        storage = '0' + national  # 05xxxxxxxx
    else:
        storage = e164
    if not (8 <= len(e164) <= 15):
        raise ValueError('invalid_national')
    return storage, e164, country['iso']


def phone_to_e164(storage_phone: str, country_iso: str | None = None) -> str:
    """Best-effort E.164 digits from stored phone."""
    digits = _digits(storage_phone)
    if not digits:
        raise ValueError('invalid_phone')
    # Already international
    if len(digits) >= 11 and not digits.startswith('0'):
        return digits
    # Legacy Saudi
    if re.match(r'^05\d{8}$', digits):
        return '966' + digits[1:]
    country = get_country(country_iso) or _BY_ISO['SA']
    national = normalize_national(country, digits)
    if re.match(country['pattern'], national):
        return country['dial'] + national
    raise ValueError('invalid_phone')


def phone_to_chat_id(storage_phone: str, country_iso: str | None = None) -> str:
    return phone_to_e164(storage_phone, country_iso) + '@c.us'
