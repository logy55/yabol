const storageKey='yabol.remembered-username';
const validUsername=value=>typeof value==='string'&&/^[a-z0-9_]{3,24}$/.test(value);

export function readRememberedUsername(storage){
  try{const value=(storage??globalThis.localStorage).getItem(storageKey);return validUsername(value)?value:'';}catch{return '';}
}
export function saveRememberedUsername(username,remember,storage){
  try{
    const target=storage??globalThis.localStorage,value=String(username??'').trim().toLowerCase();
    if(remember&&validUsername(value))target.setItem(storageKey,value);else target.removeItem(storageKey);
    return true;
  }catch{return false;}
}
export function bindRememberedLogin(form){
  const input=form.elements.username,checkbox=form.elements.remember_username;
  const save=()=>saveRememberedUsername(input.value,checkbox.checked);
  checkbox.addEventListener('change',save);
  input.addEventListener('change',()=>{if(!checkbox.disabled&&checkbox.checked)save();});
  return {
    prepare(signup){
      const saved=readRememberedUsername();
      form.querySelector('#remember-username-label').hidden=signup;
      checkbox.disabled=signup;checkbox.checked=!signup&&Boolean(saved);
      input.value=signup?'':saved;
    },
    save
  };
}
