"""Only isolated temporary databases contain test fixtures. Never production data."""
import math
import time
import sqlite3
import hashlib
import pytest
from fastapi.testclient import TestClient
from backend.app import create_app, Settings, QUALITY, MIB, cell_for, classify

@pytest.fixture
def setup(tmp_path):
    app=create_app(Settings(db=str(tmp_path/'test-only.sqlite3'),testing=True))
    client=TestClient(app)
    users=[]
    for i in range(4):
        r=client.post('/api/auth/register',json={'phone':f'050000000{i}','password':'test-only-password-2026','name':f'fixture {i}'})
        assert r.status_code==201,r.text
        users.append(r.json())
    return app,client,users

def auth(user):return {'Authorization':'Bearer '+user['token']}

def transport_result(app,client,user):
    r=client.post('/api/speed/sessions',headers=auth(user));assert r.status_code==201
    sid=r.json()['session_id'];headers={**auth(user),'X-Test-Session':sid}
    for _ in range(7):assert client.get('/api/speed/ping',headers=headers).status_code==200
    for _ in range(2):
        r=client.get('/api/speed/download',headers=headers);assert len(r.content)==2*MIB
        r=client.post('/api/speed/upload',headers=headers,content=b'fixture-binary-'*(2*MIB//15)+b'x'*(2*MIB%15))
        assert r.status_code==200,r.text
    # Deterministic timing fixture; it does NOT claim an internet measurement.
    app.state.test_sessions[sid]['started']-=5
    return {'session_id':sid,'download_mbps':4*MIB*8/2/1e6,'upload_mbps':4*MIB*8/2/1e6,'ping_ms':25.0,'download_seconds':2.0,'upload_seconds':2.0,'download_bytes':4*MIB,'upload_bytes':4*MIB,'connection_type':'unknown','connection_source':'unavailable','share_location':False,'measurement_time':time.time(),'test_status':'completed'}

def seed(app,users,*,values=None,age=3600,samples=5,lat=27.525,lon=41.695,connection='wifi'):
    values=values or [10,20,30,40,1000]
    y,x=cell_for(lat,lon)
    with app.state.database.connect() as db:
        for i in range(samples):
            timestamp=time.time()-age-i*3600
            db.execute('''INSERT INTO network_measurements(id,user_id,download_mbps,upload_mbps,ping_ms,connection_type,connection_source,cell_y,cell_x,measurement_time,created_at,test_status,server_id,session_id,hour_bucket) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (f'test-{lat}-{age}-{i}',users[i%len(users)]['user']['id'],values[i%len(values)],5+i,20+i,connection,'os_interface',y,x,timestamp,time.time(),'completed','isolated-test',f'fixture-{lat}-{age}-{i}',int(timestamp//3600)))

def test_real_bytes_receipt_save_and_private_history(setup):
    app,c,users=setup
    body=transport_result(app,c,users[0])
    r=c.post('/api/network-tests',headers=auth(users[0]),json=body)
    assert r.status_code==201,r.text
    assert r.json()['shared'] is False
    assert c.get('/api/network-tests/mine',headers=auth(users[0])).json()['items'][0]['download_mbps']==body['download_mbps']
    assert c.get('/api/network-tests/mine',headers=auth(users[1])).json()['items']==[]
    assert c.get('/api/network-heatmap').json()['cells']==[]
    assert c.post('/api/network-tests',headers=auth(users[0]),json=body).status_code==409

@pytest.mark.parametrize('change',[{'download_mbps':-1},{'ping_ms':float('inf')},{'latitude':91.0,'longitude':41.7,'share_location':True,'location_accuracy_m':100.0},{'latitude':25.0,'longitude':46.0,'share_location':True,'location_accuracy_m':100.0},{'latitude':27.52,'longitude':41.69},{'carrier_name':'guessed-stc'},{'download_bytes':1},{'download_mbps':9000.0},{'connection_type':'wifi','connection_source':'unavailable'}])
def test_invalid_measurement_is_rejected(setup,change):
    app,c,users=setup
    body=transport_result(app,c,users[0]);body.update(change)
    if math.isinf(body['ping_ms']):
        response=c.post('/api/network-tests',headers={**auth(users[0]),'Content-Type':'application/json'},content='{"ping_ms":1e999}')
    else:response=c.post('/api/network-tests',headers=auth(users[0]),json=body)
    assert response.status_code==422,response.text
    with app.state.database.connect() as db:assert db.execute('SELECT count(*) FROM network_measurements').fetchone()[0]==0

def test_publication_grid_privacy_and_statistics(setup):
    app,c,users=setup;seed(app,users)
    response=c.get('/api/network-heatmap');assert response.status_code==200
    data=response.json();cell=data['cells'][0]
    assert cell['sample_count']==5
    assert cell['statistics']['download_mbps']=={'mean':220.0,'median':30.0}
    assert cell['statistics']['upload_mbps']['median']==7
    assert cell['quality']['download']=='moderate'
    assert cell['bounds']==[41.69,27.52,41.7,27.53]
    text=response.text
    assert all(key not in text for key in ['user_id','phone','latitude','longitude','session_id'])
    assert c.get('/api/network-areas/'+cell['id']).json()['cell']['id']==cell['id']
    assert c.get('/api/network-statistics').json()['sample_count']==5

def test_single_contributor_is_not_exposed_even_for_density(setup):
    app,c,users=setup;seed(app,[users[0]],samples=12)
    assert c.get('/api/network-heatmap?metric=density').json()['cells']==[]
    mine=c.get('/api/network-heatmap/mine',headers=auth(users[0])).json()['cells']
    assert len(mine)==1 and mine[0]['status']=='personal' and mine[0]['sample_count']==12
    assert c.get('/api/network-heatmap/mine',headers=auth(users[1])).json()['cells']==[]

def test_small_sample_is_gray_and_unclassified(setup):
    app,c,users=setup;seed(app,users,samples=3)
    cell=c.get('/api/network-heatmap').json()['cells'][0]
    assert cell['status']=='insufficient' and cell['statistics'] is None and cell['sample_count'] is None and cell['quality'] is None

def test_stale_data_not_classified_as_current(setup):
    app,c,users=setup;seed(app,users,age=4*86400)
    cell=c.get('/api/network-heatmap').json()['cells'][0]
    assert cell['status']=='stale' and cell['quality']['download']=='stale'

def test_filters_recompute_statistics_and_sample_sufficiency(setup):
    app,c,users=setup;seed(app,users)
    assert c.get('/api/network-heatmap?connection=cellular').json()['cells']==[]
    assert c.get('/api/network-heatmap?min_download=25').json()['cells'][0]['status']=='insufficient'
    assert c.get('/api/network-heatmap?min_samples=10').json()['cells'][0]['status']=='insufficient'
    assert c.get('/api/network-heatmap?bbox=40,26,40.1,26.1').json()['cells']==[]
    assert c.get('/api/network-heatmap',params={'start':time.time()-1200,'end':time.time()}).json()['cells']==[]
    assert c.get('/api/network-heatmap?carrier=stc').status_code==422
    assert c.get('/api/network-heatmap?min_samples=1').status_code==422
    assert c.get('/api/network-heatmap?bbox=nan,27,42,28').status_code==422
    assert c.get('/api/network-heatmap?start=0&end=999999999999').status_code==422

def test_map_updates_after_new_rows_and_deletion(setup):
    app,c,users=setup;assert c.get('/api/network-heatmap').json()['cells']==[]
    seed(app,users)
    assert len(c.get('/api/network-heatmap').json()['cells'])==1
    assert c.delete('/api/network-tests/mine',headers=auth(users[0])).status_code==204
    assert c.get('/api/network-heatmap').json()['cells'][0]['status']=='insufficient'

def test_auth_logout_request_limits_and_no_receipt(setup):
    app,c,users=setup
    assert c.get('/api/network-tests/mine').status_code==401
    assert c.post('/api/network-tests',json={}).status_code==401
    assert c.post('/api/auth/login',json={'phone':'0500000000','password':'wrong-password-123'}).status_code==401
    assert c.post('/api/auth/login',json={'phone':'0500000000','password':'test-only-password-2026'}).status_code==200
    assert c.post('/api/auth/login',content=b'x'*20000).status_code==413
    assert c.get('/api/network-config',headers={'Origin':'https://untrusted.test'}).status_code==403
    assert c.delete('/api/auth/session',headers=auth(users[0])).status_code==204
    assert c.get('/api/network-tests/mine',headers=auth(users[0])).status_code==401

def test_disabled_local_server_never_fabricates_a_test(tmp_path):
    app=create_app(Settings(db=str(tmp_path/'empty.sqlite3')));c=TestClient(app)
    user=c.post('/api/auth/register',json={'phone':'0511111111','password':'local-password-only'}).json()
    assert c.get('/api/network-config').json()['test']['available'] is False
    assert c.post('/api/speed/sessions',headers=auth(user)).status_code==503
    assert c.get('/api/network-heatmap').json()['cells']==[]

def test_loopback_speed_can_be_enabled_for_development(tmp_path):
    app=create_app(Settings(db=str(tmp_path/'local-speed.sqlite3'),speed_enabled=True,public_origin='http://localhost:8765'))
    c=TestClient(app)
    cfg=c.get('/api/network-config').json()['test']
    assert cfg['available'] is True
    assert cfg['mode']=='local'
    assert cfg['server_id']=='http://localhost:8765'
    user=c.post('/api/auth/register',json={'phone':'0511111112','password':'local-password-only'}).json()
    assert c.post('/api/speed/sessions',headers=auth(user)).status_code==201

def test_coordinate_quantization_and_quality():
    assert cell_for(27.525123,41.695987)==(2752,4169)
    assert classify(50,'download')=='good'
    assert classify(4.9,'download')=='very_poor'
    assert classify(201,'ping')=='very_poor'

def test_browser_transfer_preflight(setup):
    app,c,users=setup
    r=c.options('/api/speed/download',headers={'Origin':'http://localhost:8080','Access-Control-Request-Method':'GET','Access-Control-Request-Headers':'authorization,x-test-session,cache-control'})
    assert r.status_code==200
    assert r.headers['access-control-allow-origin']=='http://localhost:8080'

def test_public_location_is_cell_only_and_no_double_contribution(setup):
    app,c,users=setup;body=transport_result(app,c,users[0]);body.update(share_location=True,latitude=27.525123,longitude=41.695987,location_accuracy_m=123.4)
    assert c.post('/api/network-tests',headers=auth(users[0]),json=body).status_code==201
    with app.state.database.connect() as db:
        row=dict(db.execute('SELECT * FROM network_measurements').fetchone())
        assert row['cell_y']==2752 and row['cell_x']==4169
        assert 'latitude' not in row and 'longitude' not in row
        assert row['location_accuracy_m']==200
    body2=transport_result(app,c,users[0]);body2.update(share_location=True,latitude=27.525,longitude=41.695,location_accuracy_m=200.0)
    assert c.post('/api/network-tests',headers=auth(users[0]),json=body2).status_code==409

def test_retention_and_account_erasure(setup):
    app,c,users=setup;seed(app,users,age=100*86400)
    assert c.get('/api/network-heatmap').json()['cells']==[]
    with app.state.database.connect() as db:assert db.execute('SELECT count(*) FROM network_measurements').fetchone()[0]==0
    assert c.delete('/api/auth/account',headers=auth(users[0])).status_code==204
    assert c.get('/api/network-tests/mine',headers=auth(users[0])).status_code==401

def test_bounded_aggregation_performance(setup):
    app,c,users=setup
    seed(app,users,samples=2000,values=[25,30,35])
    start=time.monotonic();r=c.get('/api/network-heatmap?start='+str(time.time()-89*86400))
    assert r.status_code==200 and r.json()['cells']
    assert time.monotonic()-start<5
    assert len(r.content)<10000

def test_legacy_password_hash_migrates_on_login(tmp_path):
    path=tmp_path/'legacy-test-only.sqlite3'
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE users(id TEXT PRIMARY KEY,phone TEXT UNIQUE,name TEXT,salt TEXT,password_hash TEXT)')
        salt='01'*16
        digest=hashlib.pbkdf2_hmac('sha256',b'legacy-test-password',bytes.fromhex(salt),310000).hex()
        db.execute('INSERT INTO users VALUES(?,?,?,?,?)',('legacy','0522222222','test',salt,digest))
    app=create_app(Settings(db=str(path)))
    c=TestClient(app)
    assert c.post('/api/auth/login',json={'phone':'0522222222','password':'legacy-test-password'}).status_code==200
    with app.state.database.connect() as db:
        assert db.execute('SELECT hash_iterations FROM users').fetchone()[0]==600000

def test_retention_lifespan_starts_and_stops_cleanly(tmp_path):
    app=create_app(Settings(db=str(tmp_path/'lifecycle-test-only.sqlite3')))
    with TestClient(app) as c:
        assert c.get('/api/network-config').status_code==200
