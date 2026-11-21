import assert from 'node:assert/strict';

const project='demo-inventory';
function endpoint(env) {
  const host=process.env[env];
  assert.match(host??'',/^(127\.0\.0\.1|localhost):\d+$/);
  return 'http://'+host;
}
const db=endpoint('FIRESTORE_EMULATOR_HOST')+'/v1/projects/'+project+'/databases/(default)/documents';
const auth=endpoint('FIREBASE_AUTH_EMULATOR_HOST')+'/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local';
const prefix='projects/'+project+'/databases/(default)/documents/';
const id=c=>c.repeat(20);
const product=id('P'), supplier=id('S'), transfer=id('T'), order=id('O');
const source='warehouse', destination='tnhb';
const balancePath=loc=>'is_balances/'+loc+'_'+product;
const stamp=Symbol('server timestamp');
let uid, token;

async function request(url,{method='GET',credential,body}={},expected=200) {
  const response=await fetch(url,{method,headers:{
    ...(credential?{Authorization:'Bearer '+credential}:{}),
    ...(body?{'Content-Type':'application/json'}:{})},
    ...(body?{body:JSON.stringify(body)}:{}),
  });
  const data=await response.json();
  assert.equal(response.status,expected,JSON.stringify(data).slice(0,1250));
  return data;
}
const asField=v=>v===null?{nullValue:null}:typeof v==='number'
  ?{integerValue:String(v)}:typeof v==='boolean'?{booleanValue:v}:{stringValue:v};
function write(path,values,{update=false}={}) {
  const ordinary=Object.entries(values).filter(([,v])=>v!==stamp);
  const timestamps=Object.entries(values).filter(([,v])=>v===stamp);
  return {update:{name:prefix+path,fields:Object.fromEntries(ordinary.map(([k,v])=>[k,asField(v)]))},
    ...(update?{updateMask:{fieldPaths:ordinary.map(([k])=>k)}}:{}),
    ...(timestamps.length?{updateTransforms:timestamps.map(([k])=>({fieldPath:k,setToServerValue:'REQUEST_TIME'}))}:{})};
}
const commit=(writes,credential=token,status=200)=>request(db+':commit',{method:'POST',credential,body:{writes}},status);
const quantity=async loc=>Number((await request(db+'/'+balancePath(loc),{credential:'owner'})).fields.quantity.integerValue);
function movement(moveId,type,loc,before,units,delta,workflowId) {
  return [
    write(balancePath(loc),{productId:product,location:loc,quantity:before+delta,lastMovementId:moveId,at:stamp}),
    write('is_movements/'+moveId,{type,location:loc,productId:product,quantity:units,note:'',
      ...(workflowId?{workflowId}:{}),balanceId:loc+'_'+product,before,delta,quantityAfter:before+delta,actor:uid,at:stamp}),
  ];
}
const account=await request(auth,{method:'POST',body:{email:'admin@example.test',password:'test-password',returnSecureToken:true}});
uid=account.localId; token=account.idToken;
const other=await request(auth,{method:'POST',body:{email:'staff@example.test',password:'test-password',returnSecureToken:true}});
await commit([write('users/'+uid,{active:true,role:'admin'})],'owner');
const supplierWrite=write('is_suppliers/'+supplier,{name:'Fixture supplier',phone:'',email:'',notes:'',active:true,actor:uid,at:stamp});
await commit([supplierWrite],other.idToken,403);
await commit([supplierWrite]);
await commit([write('is_products/'+product,{name:'Tester',sku:'T1',category:'Demo',barcode:'00014',supplierId:supplier,unitCost:2499,reorder:3,active:true,actor:uid,at:stamp})]);
await commit(movement(id('I'),'opening',source,0,12,12));
await commit(movement(id('V'),'sale',source,12,1,-1));
assert.equal(await quantity(source),11);

const dispatchId=id('D');
const arrive=id('A');
const record=write('is_transfers/'+transfer,{productId:product,from:source,to:destination,quantity:4,status:'received',
  dispatchId,receiveId:arrive,receiptActor:uid,receivedAt:stamp,actor:uid,at:stamp});
await commit([record],token,403);
await commit(movement(dispatchId,'transfer_out',source,11,4,-4,transfer),token,403);
const outbound=movement(dispatchId,'transfer_out',source,11,4,-4,transfer);
const inbound=movement(arrive,'transfer_in',destination,0,4,4,transfer);
await commit([...outbound,record],token,403);
await commit([...inbound,record],token,403);
await commit([...outbound,...movement(arrive,'transfer_in',destination,0,3,3,transfer),record],token,403);
assert.equal(await quantity(source),11);
await request(db+'/'+balancePath(destination),{credential:'owner'},404);
await commit([...outbound,...inbound,record]);
await commit([...outbound,...inbound,record],token,403);
assert.equal(await quantity(source),7);
assert.equal(await quantity(destination),4);

const older=id('L'), oldDispatch=id('J'), oldReceipt=id('K'), oldDestination='hotelmart';
const oldRecord=write('is_transfers/'+older,{productId:product,from:source,to:oldDestination,quantity:1,status:'in_transit',
  dispatchId:oldDispatch,receiveId:null,receiptActor:null,receivedAt:null,actor:uid,at:stamp});
const oldOutbound=movement(oldDispatch,'transfer_out',source,7,1,-1,older);
await commit([...oldOutbound,oldRecord],token,403);
// Seed a record created by the pre-upgrade workflow; source stock is already debited.
await commit([...oldOutbound,oldRecord],'owner');
const finishOlder=write('is_transfers/'+older,{status:'received',receiveId:oldReceipt,receiptActor:uid,receivedAt:stamp},{update:true});
await commit([...movement(oldReceipt,'transfer_in',oldDestination,0,1,1,older),finishOlder]);
assert.equal(await quantity(source),6);
assert.equal(await quantity(oldDestination),1);

await commit([write('is_orders/'+order,{supplierId:supplier,productId:product,location:destination,quantity:6,received:0,unitCost:2599,
  reference:'P-001',status:'ordered',lastReceiptId:null,actor:uid,at:stamp,updatedAt:stamp})]);
assert.equal(await quantity(destination),4);
function receipt(moveId,before,units,received,status) {
  return [
    ...movement(moveId,'purchase_receipt',destination,before,units,units,order),
    write('is_orders/'+order,{received,status,lastReceiptId:moveId,updatedAt:stamp},{update:true}),
  ];
}
await commit(receipt(id('B'),4,2,2,'partial'));
await commit(receipt(id('C'),6,5,7,'partial'),token,403);
await commit(receipt(id('E'),6,4,6,'received'));
await commit(receipt(id('Z'),10,1,7,'received'),token,403);
assert.equal(await quantity(destination),10);
const extraProduct=id('Q'), first=id('X'), second=id('Y');
await commit([write('is_products/'+extraProduct,{name:'Second item',sku:'T2',category:'',reorder:null,active:true,actor:uid,at:stamp})]);
const purchaseLine=item=>({supplierId:supplier,productId:item,location:destination,quantity:2,received:0,
  unitCost:null,reference:'P-002',status:'ordered',lastReceiptId:null,actor:uid,at:stamp,updatedAt:stamp});
await commit([write('is_orders/'+first,purchaseLine(product)),write('is_orders/'+second,purchaseLine(extraProduct))]);
await commit([write('is_orders/'+first,{status:'cancelled',updatedAt:stamp},{update:true})]);
assert.equal(await quantity(destination),10);
await commit([write('is_orders/'+second,{status:'received',received:2,lastReceiptId:id('R'),updatedAt:stamp},{update:true})],token,403);
console.log('Verified that immediate transfers post both branches or neither, cannot be repeated, preserve older transfers, and do not break purchasing.');

const productPath='is_products/'+product;
const recycle=write(productPath,{active:false,activeBeforeDelete:true,deletedAt:stamp,actor:uid,at:stamp},{update:true});
await commit([recycle],other.idToken,403);
await commit([write(productPath,{active:false,activeBeforeDelete:true,deletedAt:stamp,name:'Changed',actor:uid,at:stamp},{update:true})],token,403);
await commit([recycle]);
await commit(movement(id('S'),'sale',source,6,1,-1),token,403);
await commit([write(productPath,{name:'Changed'},{update:true})],token,403);
await commit([{delete:prefix+productPath}],token,403);
const restore=write(productPath,{active:true,actor:uid,at:stamp},{update:true});
restore.updateMask.fieldPaths.push('deletedAt','activeBeforeDelete');
await commit([restore]);
const restored=(await request(db+'/'+productPath,{credential:'owner'})).fields;
assert.equal(restored.active.booleanValue,true);
assert.equal(restored.deletedAt,undefined);
assert.equal(await quantity(source),6);
assert.equal(await quantity(destination),10);
console.log('Verified reversible product recycling, access guards and preserved stock.');

// Mirror report reads: branch equality plus a stable document ID cursor.
const runReportQuery=(collection, cursor, credential=token)=>request(db+':runQuery',{
  method:'POST', credential,
  body:{structuredQuery:{
    from:[{collectionId:collection}],
    where:{fieldFilter:{field:{fieldPath:'location'},op:'EQUAL',value:{stringValue:source}}},
    orderBy:[{field:{fieldPath:'__name__'},direction:'ASCENDING'}],
    limit:1,
    ...(cursor?{startAt:{values:[{referenceValue:cursor}],before:false}}:{}),
  }},
},credential===token?200:403);
await commit(movement(id('S'),'damage',source,6,1,-1));
const firstPage=await runReportQuery('is_movements');
const firstDoc=firstPage[0].document;
assert.equal(firstDoc.fields.location.stringValue,source);
const nextPage=await runReportQuery('is_movements',firstDoc.name);
assert.notEqual(nextPage[0].document.name,firstDoc.name);
assert.equal(nextPage[0].document.fields.location.stringValue,source);
assert.equal((await runReportQuery('is_balances'))[0].document.fields.quantity.integerValue,'5');
await runReportQuery('is_movements',undefined,other.idToken);
console.log('Verified admin report reads, branch filtering, and pagination.');
