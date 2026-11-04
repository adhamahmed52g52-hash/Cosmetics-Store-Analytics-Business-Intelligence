-- ******************************************************
--                 Create Database
-- ******************************************************

use master;
go

-- التأكد لو الداتابيز موجودة قبل كدة بنحذفها عشان نبدأ على نظيف
if exists (select name from sys.databases where name = 'cosmetics_store')
begin
    alter database cosmetics_store set single_user with rollback immediate; --> بنقفل أي اتصال مفتوح بالداتابيز عشان نعرف نحذفها
    drop database cosmetics_store; --> حذف الداتابيز القديمة
end
go

---------------------------------------------
--1) إنشاء قاعدة البيانات ودعم الحروف العربي
---------------------------------------------
create database cosmetics_store
collate Arabic_100_CI_AS; --> Arabic_100_CI_AS عشان يقبل الحروف العربي و Case Insensitive مبيفرقش بين الحروف الكبيرة والصغيرة
go
