// Allocate whole won per expense so every share and transfer conserves the total.
export function settleGroupExpenses(people,expenses){
  if(people.length<2||people.length>20||new Set(people).size!==people.length)throw new Error('참여자를 확인해 주세요.');
  const bal=Object.fromEntries(people.map(name=>[name,0])),allocations=[];
  for(const expense of expenses){
    if(!Number.isSafeInteger(expense.amount)||expense.amount<1||expense.amount>1_000_000_000_000||!people.includes(expense.payer)||!expense.members.length||new Set(expense.members).size!==expense.members.length||expense.members.some(name=>!people.includes(name)))throw new Error('지출 금액과 참여자를 확인해 주세요.');
    const members=people.filter(name=>expense.members.includes(name)),base=Math.floor(expense.amount/members.length),remainder=expense.amount%members.length;
    const shares=Object.fromEntries(members.map((name,index)=>[name,base+(index<remainder?1:0)]));
    bal[expense.payer]+=expense.amount;for(const [name,share] of Object.entries(shares))bal[name]-=share;allocations.push(shares);
  }
  const debts=people.filter(name=>bal[name]<0).map(name=>({name,amount:-bal[name]})).sort((a,b)=>b.amount-a.amount),credits=people.filter(name=>bal[name]>0).map(name=>({name,amount:bal[name]})).sort((a,b)=>b.amount-a.amount),txs=[];
  let i=0,j=0;while(i<debts.length&&j<credits.length){const amount=Math.min(debts[i].amount,credits[j].amount);txs.push({from:debts[i].name,to:credits[j].name,amt:amount});debts[i].amount-=amount;credits[j].amount-=amount;if(!debts[i].amount)i++;if(!credits[j].amount)j++;}
  return{bal,txs,allocations};
}
